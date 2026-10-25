package com.suvi.gallery.data.ml

import com.suvi.gallery.data.local.converter.Converters
import com.suvi.gallery.data.local.dao.FaceVaultDao
import com.suvi.gallery.data.local.entity.FaceEntity
import com.suvi.gallery.data.local.entity.PersonEntity
import kotlin.math.sqrt

class KotlinDBSCAN(
    private val eps: Float = 0.42f,
    private val minSamples: Int = 2
) {
    private val converters = Converters()

    private fun cosineDistance(a: FloatArray, b: FloatArray): Float {
        var dot = 0f
        var normA = 0f
        var normB = 0f
        for (i in a.indices) {
            dot += a[i] * b[i]
            normA += a[i] * a[i]
            normB += b[i] * b[i]
        }
        val sim = if (normA == 0f || normB == 0f) 0f else dot / (sqrt(normA) * sqrt(normB))
        return 1.0f - sim
    }

    suspend fun clusterAndAssign(
        unassignedFaces: List<FaceEntity>,
        dao: FaceVaultDao
    ) {
        if (unassignedFaces.isEmpty()) return

        val allFaces = dao.getAllFaces()
        val assignedFaces = allFaces.filter { it.personId != null }

        // Step 1: Compute Centroids for existing named/clustered people
        val personCentroids = mutableMapOf<Long, FloatArray>()
        if (assignedFaces.isNotEmpty()) {
            val groupedByPerson = assignedFaces.groupBy { it.personId!! }
            for ((personId, faces) in groupedByPerson) {
                val vectors = faces.mapNotNull { converters.toFloatArray(it.embedding) }
                if (vectors.isNotEmpty()) {
                    val centroid = FloatArray(vectors[0].size)
                    for (vec in vectors) {
                        for (i in vec.indices) centroid[i] += vec[i]
                    }
                    var norm = 0f
                    for (i in centroid.indices) {
                        centroid[i] = centroid[i] / vectors.size
                        norm += centroid[i] * centroid[i]
                    }
                    val l2 = sqrt(norm)
                    if (l2 > 0f) {
                        for (i in centroid.indices) {
                            centroid[i] = centroid[i] / l2
                        }
                    }
                    personCentroids[personId] = centroid
                }
            }
        }

        // Step 2: Try matching unassigned faces to existing person centroids first
        val remainingFaces = mutableListOf<FaceEntity>()
        for (face in unassignedFaces) {
            val emb = converters.toFloatArray(face.embedding) ?: continue
            var bestPersonId: Long? = null
            var lowestDistance = 1.0f

            for ((personId, centroid) in personCentroids) {
                val dist = cosineDistance(emb, centroid)
                if (dist < lowestDistance) {
                    lowestDistance = dist
                    bestPersonId = personId
                }
            }

            // High confidence match (distance <= 0.38 => similarity >= 0.62)
            if (bestPersonId != null && lowestDistance <= 0.38f) {
                dao.assignFacesToPerson(listOf(face.faceId), bestPersonId)
            } else {
                remainingFaces.add(face)
            }
        }

        if (remainingFaces.size < minSamples) return

        // Step 3: Run DBSCAN on the remaining unassigned faces
        val faceVectors = remainingFaces.mapNotNull { face ->
            converters.toFloatArray(face.embedding)?.let { face to it }
        }

        val n = faceVectors.size
        val clusterLabels = IntArray(n) { -1 } // -1 = unclassified / noise
        var currentCluster = 0

        for (i in 0 until n) {
            if (clusterLabels[i] != -1) continue

            val neighbors = mutableListOf<Int>()
            for (j in 0 until n) {
                if (cosineDistance(faceVectors[i].second, faceVectors[j].second) <= eps) {
                    neighbors.add(j)
                }
            }

            if (neighbors.size >= minSamples) {
                clusterLabels[i] = currentCluster
                val visitedInCluster = BooleanArray(n)
                visitedInCluster[i] = true
                val queue = ArrayDeque<Int>()
                for (idx in neighbors) {
                    if (idx != i) {
                        visitedInCluster[idx] = true
                        queue.add(idx)
                    }
                }

                while (queue.isNotEmpty()) {
                    val current = queue.removeFirst()
                    if (clusterLabels[current] == -1) {
                        clusterLabels[current] = currentCluster
                    }

                    val subNeighbors = mutableListOf<Int>()
                    for (k in 0 until n) {
                        if (cosineDistance(faceVectors[current].second, faceVectors[k].second) <= eps) {
                            subNeighbors.add(k)
                        }
                    }

                    if (subNeighbors.size >= minSamples) {
                        for (k in subNeighbors) {
                            if (!visitedInCluster[k]) {
                                visitedInCluster[k] = true
                                queue.add(k)
                                if (clusterLabels[k] == -1) {
                                    clusterLabels[k] = currentCluster
                                }
                            }
                        }
                    }
                }
                currentCluster++
            }
        }

        // Step 4: Create new Person records for discovered clusters
        val clusters = mutableMapOf<Int, MutableList<Long>>()
        for (i in 0 until n) {
            val label = clusterLabels[i]
            if (label >= 0) {
                clusters.getOrPut(label) { mutableListOf() }.add(faceVectors[i].first.faceId)
            }
        }

        for ((_, faceIds) in clusters) {
            val personId = dao.insertPerson(
                PersonEntity(
                    name = "Person #${System.currentTimeMillis() % 10000}",
                    avatarFaceId = faceIds.firstOrNull()
                )
            )
            dao.assignFacesToPerson(faceIds, personId)
        }

        dao.refreshPersonStats()
    }
}
