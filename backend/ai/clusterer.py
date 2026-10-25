import numpy as np
from sklearn.cluster import DBSCAN
from typing import List, Dict, Tuple, Optional
from ..storage.db import Database

class FaceClusterer:
    def __init__(self, db: Database, eps: float = 0.42, min_samples: int = 2):
        """
        eps: Maximum cosine distance between two samples for one to be considered as in the neighborhood of the other.
        min_samples: The number of samples in a neighborhood for a point to be considered as a core point.
        """
        self.db = db
        self.eps = eps
        self.min_samples = min_samples

    def cluster_all_unassigned_faces(self) -> Dict[str, int]:
        """
        Fetches all unassigned faces, runs DBSCAN clustering, creates new Person entries for clusters,
        and assigns faces accordingly.
        """
        faces = self.db.get_all_face_embeddings()
        if not faces:
            return {"clusters_created": 0, "faces_assigned": 0}

        # Separate already assigned vs unassigned
        assigned_faces = [f for f in faces if f["person_id"] is not None]
        unassigned_faces = [f for f in faces if f["person_id"] is None]

        if not unassigned_faces:
            return {"clusters_created": 0, "faces_assigned": 0}

        # Step 1: Compute centroids for existing named people
        people_centroids = {}
        if assigned_faces:
            person_groups = {}
            for f in assigned_faces:
                pid = f["person_id"]
                if pid not in person_groups:
                    person_groups[pid] = []
                person_groups[pid].append(f["embedding"])
            
            for pid, embs in person_groups.items():
                mean_emb = np.mean(embs, axis=0)
                norm = np.linalg.norm(mean_emb)
                if norm > 0:
                    people_centroids[pid] = mean_emb / norm

        # Step 2: Try to match unassigned faces to existing people centroids first
        matched_to_existing = 0
        remaining_unassigned = []

        for f in unassigned_faces:
            emb = f["embedding"]
            norm = np.linalg.norm(emb)
            if norm > 0:
                emb = emb / norm
            
            best_pid = None
            best_sim = -1.0

            for pid, centroid in people_centroids.items():
                # Cosine similarity = dot product of unit vectors
                sim = float(np.dot(emb, centroid))
                if sim > best_sim:
                    best_sim = sim
                    best_pid = pid

            # High confidence threshold for auto-matching to existing person (cosine distance < 0.38 => sim > 0.62)
            if best_pid is not None and best_sim >= 0.62:
                self.db.assign_faces_to_person([f["id"]], best_pid)
                matched_to_existing += 1
            else:
                remaining_unassigned.append(f)

        if len(remaining_unassigned) < 2:
            return {"clusters_created": 0, "faces_assigned": matched_to_existing}

        # Step 3: Run DBSCAN on the remaining unassigned faces
        X = np.stack([f["embedding"] for f in remaining_unassigned])
        # Normalize
        norms = np.linalg.norm(X, axis=1, keepdims=True)
        norms[norms == 0] = 1.0
        X_norm = X / norms

        dbscan = DBSCAN(eps=self.eps, min_samples=self.min_samples, metric="cosine")
        labels = dbscan.fit_predict(X_norm)

        # Step 4: Group faces by cluster label
        clusters = {}
        for idx, label in enumerate(labels):
            if label != -1:  # -1 is noise
                if label not in clusters:
                    clusters[label] = []
                clusters[label].append(remaining_unassigned[idx])

        # Step 5: For each valid cluster, create a Person entry (or Person #) and assign faces
        clusters_created = 0
        faces_assigned = matched_to_existing

        with self.db.get_connection() as conn:
            cur = conn.cursor()
            cur.execute("SELECT COUNT(*) FROM people")
            person_counter = cur.fetchone()[0] + 1

        for label, cluster_faces in clusters.items():
            face_ids = [f["id"] for f in cluster_faces]
            # Use the first face as the initial avatar
            avatar_id = face_ids[0]
            person_name = f"Person #{person_counter}"
            person_counter += 1

            person_id = self.db.create_or_get_person(person_name, avatar_face_id=avatar_id)
            self.db.assign_faces_to_person(face_ids, person_id)
            clusters_created += 1
            faces_assigned += len(face_ids)

        return {"clusters_created": clusters_created, "faces_assigned": faces_assigned}
