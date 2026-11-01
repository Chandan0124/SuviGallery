import numpy as np
from sklearn.cluster import DBSCAN
from typing import List, Dict, Tuple, Optional
from ..storage.db import Database

class FaceClusterer:
    def __init__(self, db: Database, eps: float = 0.34, min_samples: int = 4, min_photos_per_person: int = 5):
        """
        eps: Maximum cosine distance between two samples (0.34 = 66% cosine similarity threshold).
        min_samples: Minimum core points for DBSCAN (avoids 1-2 random photobomber clusters).
        min_photos_per_person: Minimum distinct photos required to promote a cluster to a Person card.
        """
        self.db = db
        self.eps = eps
        self.min_samples = min_samples
        self.min_photos_per_person = min_photos_per_person

    def recluster_unnamed_faces(self) -> Dict[str, int]:
        """
        Safely re-clusters ONLY unnamed faces ('Person #...').
        ALL explicitly named people (e.g. Mummy, Maa, Krishiv, etc.) remain 100% preserved.
        Enforces CANNOT-LINK constraints (two faces from the same image can NEVER belong to the same person).
        Filters out background noise with < min_photos_per_person.
        """
        with self.db.get_connection() as conn:
            cur = conn.cursor()
            # 1. Unassign faces from unnamed people
            cur.execute("""
                UPDATE faces 
                SET person_id = NULL 
                WHERE person_id IN (SELECT id FROM people WHERE name LIKE 'Person #%')
            """)
            # 2. Remove unnamed people records
            cur.execute("DELETE FROM people WHERE name LIKE 'Person #%'")
            conn.commit()

        # 3. Re-run clustering with cannot-link and strict thresholds
        return self.cluster_all_unassigned_faces()

    def cluster_all_unassigned_faces(self) -> Dict[str, int]:
        """
        Fetches all unassigned faces, matches high-confidence faces to named people centroids
        with CANNOT-LINK enforcement, runs DBSCAN on remaining faces, and creates new Person
        records only for clusters meeting the minimum photo threshold.
        """
        faces = self.db.get_all_face_embeddings()
        if not faces:
            return {"clusters_created": 0, "faces_assigned": 0}

        # 1. Separate named people faces vs unassigned faces
        assigned_faces = [f for f in faces if f["person_id"] is not None]
        unassigned_faces = [f for f in faces if f["person_id"] is None]

        if not unassigned_faces:
            return {"clusters_created": 0, "faces_assigned": 0}

        # 2. Compute centroids and existing image sets for named people
        people_centroids = {}
        person_images = {}
        if assigned_faces:
            person_groups = {}
            for f in assigned_faces:
                pid = f["person_id"]
                if pid not in person_groups:
                    person_groups[pid] = []
                    person_images[pid] = set()
                person_groups[pid].append(f["embedding"])
                person_images[pid].add(f["image_id"])

            for pid, embs in person_groups.items():
                mean_emb = np.mean(embs, axis=0)
                norm = np.linalg.norm(mean_emb)
                if norm > 0:
                    people_centroids[pid] = mean_emb / norm

        # 3. Match unassigned faces to named people centroids (Cosine sim >= 0.65, CANNOT-LINK)
        matched_to_existing = 0
        remaining_unassigned = []

        for f in unassigned_faces:
            emb = f["embedding"]
            norm = np.linalg.norm(emb)
            if norm > 0:
                emb = emb / norm
            f["norm_embedding"] = emb

            img_id = f["image_id"]
            best_pid = None
            best_sim = -1.0

            for pid, centroid in people_centroids.items():
                # CANNOT-LINK: A person cannot appear twice in the same photo
                if img_id in person_images.get(pid, set()):
                    continue

                sim = float(np.dot(emb, centroid))
                if sim > best_sim:
                    best_sim = sim
                    best_pid = pid

            # Strict threshold for auto-matching to named family members (cosine similarity >= 0.65)
            if best_pid is not None and best_sim >= 0.65:
                self.db.assign_faces_to_person([f["id"]], best_pid)
                person_images[best_pid].add(img_id)
                matched_to_existing += 1
            else:
                remaining_unassigned.append(f)

        if len(remaining_unassigned) < self.min_samples:
            return {"clusters_created": 0, "faces_assigned": matched_to_existing}

        # 4. Run DBSCAN with strict eps=0.34 and min_samples=4
        X = np.stack([f["norm_embedding"] for f in remaining_unassigned])
        dbscan = DBSCAN(eps=self.eps, min_samples=self.min_samples, metric="cosine")
        labels = dbscan.fit_predict(X)

        # 5. Group faces by cluster label
        clusters = {}
        for idx, label in enumerate(labels):
            if label != -1:  # -1 is noise/background
                if label not in clusters:
                    clusters[label] = []
                clusters[label].append(remaining_unassigned[idx])

        # 6. Apply CANNOT-LINK filtering within each cluster and enforce minimum distinct photos
        clusters_created = 0
        faces_assigned = matched_to_existing

        with self.db.get_connection() as conn:
            cur = conn.cursor()
            cur.execute("SELECT COUNT(*) FROM people")
            person_counter = cur.fetchone()[0] + 1

        for label, cluster_faces in clusters.items():
            # Calculate cluster centroid
            c_embs = [f["norm_embedding"] for f in cluster_faces]
            c_mean = np.mean(c_embs, axis=0)
            c_norm = np.linalg.norm(c_mean)
            if c_norm > 0:
                c_centroid = c_mean / c_norm
            else:
                c_centroid = c_mean

            # Sort faces by similarity to centroid (closest first)
            cluster_faces_sorted = sorted(
                cluster_faces,
                key=lambda f: float(np.dot(f["norm_embedding"], c_centroid)),
                reverse=True
            )

            # Enforce CANNOT-LINK: Only 1 face per image_id allowed per person!
            seen_images = set()
            valid_faces = []
            for f in cluster_faces_sorted:
                img_id = f["image_id"]
                if img_id not in seen_images:
                    seen_images.add(img_id)
                    valid_faces.append(f)
                # Duplicate faces in the same photo are excluded (left as unassigned/unknown)

            # Only promote to a Person if this cluster spans at least min_photos_per_person distinct photos
            if len(seen_images) >= self.min_photos_per_person:
                face_ids = [f["id"] for f in valid_faces]
                avatar_id = face_ids[0]
                person_name = f"Person #{person_counter}"
                person_counter += 1

                person_id = self.db.create_or_get_person(person_name, avatar_face_id=avatar_id)
                self.db.assign_faces_to_person(face_ids, person_id)
                clusters_created += 1
                faces_assigned += len(face_ids)

        return {"clusters_created": clusters_created, "faces_assigned": faces_assigned}
