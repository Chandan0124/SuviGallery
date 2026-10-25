package com.suvi.gallery.ui.navigation

import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Folder
import androidx.compose.material.icons.filled.People
import androidx.compose.material.icons.filled.PhotoLibrary
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.navigation.NavGraph.Companion.findStartDestination
import androidx.navigation.NavType
import androidx.navigation.compose.*
import androidx.navigation.navArgument
import com.suvi.gallery.data.local.dao.FaceVaultDao
import com.suvi.gallery.ui.screens.folders.FoldersScreen
import com.suvi.gallery.ui.screens.lightbox.LightboxScreen
import com.suvi.gallery.ui.screens.people.PeopleScreen
import com.suvi.gallery.ui.screens.people.PeopleViewModel
import com.suvi.gallery.ui.screens.person_detail.PersonDetailScreen
import com.suvi.gallery.ui.screens.person_detail.PersonDetailViewModel
import com.suvi.gallery.ui.screens.photos.PhotosScreen
import com.suvi.gallery.ui.screens.photos.PhotosViewModel
import com.suvi.gallery.ui.theme.PrimaryBlue
import com.suvi.gallery.ui.theme.SurfaceDark
import com.suvi.gallery.ui.theme.TextSecondary

sealed class Screen(val route: String, val title: String, val icon: ImageVector) {
    data object Photos : Screen("photos", "Photos", Icons.Default.PhotoLibrary)
    data object Folders : Screen("folders", "Folders", Icons.Default.Folder)
    data object People : Screen("people", "People", Icons.Default.People)
}

@Composable
fun NavGraph(dao: FaceVaultDao) {
    val navController = rememberNavController()
    val navBackStackEntry by navController.currentBackStackEntryAsState()
    val currentRoute = navBackStackEntry?.destination?.route

    val bottomNavItems = listOf(
        Screen.Photos,
        Screen.Folders,
        Screen.People
    )

    val showBottomBar = currentRoute in bottomNavItems.map { it.route }

    Scaffold(
        bottomBar = {
            if (showBottomBar) {
                NavigationBar(
                    containerColor = SurfaceDark
                ) {
                    bottomNavItems.forEach { screen ->
                        NavigationBarItem(
                            icon = { Icon(screen.icon, contentDescription = screen.title) },
                            label = { Text(screen.title) },
                            selected = currentRoute == screen.route,
                            onClick = {
                                navController.navigate(screen.route) {
                                    popUpTo(navController.graph.findStartDestination().id) {
                                        saveState = true
                                    }
                                    launchSingleTop = true
                                    restoreState = true
                                }
                            },
                            colors = NavigationBarItemDefaults.colors(
                                selectedIconColor = PrimaryBlue,
                                selectedTextColor = PrimaryBlue,
                                unselectedIconColor = TextSecondary,
                                unselectedTextColor = TextSecondary,
                                indicatorColor = SurfaceDark
                            )
                        )
                    }
                }
            }
        }
    ) { innerPadding ->
        NavHost(
            navController = navController,
            startDestination = Screen.Photos.route,
            modifier = Modifier.padding(innerPadding)
        ) {
            composable(Screen.Photos.route) {
                val viewModel: PhotosViewModel = hiltViewModel()
                PhotosScreen(
                    viewModel = viewModel,
                    onPhotoClick = { photoId ->
                        navController.navigate("lightbox/$photoId")
                    }
                )
            }

            composable(Screen.Folders.route) {
                FoldersScreen(
                    dao = dao,
                    onFolderClick = { folder ->
                        // Navigate to photos with folder filter
                        navController.navigate(Screen.Photos.route)
                    }
                )
            }

            composable(Screen.People.route) {
                val viewModel: PeopleViewModel = hiltViewModel()
                PeopleScreen(
                    viewModel = viewModel,
                    onPersonClick = { personId ->
                        navController.navigate("person_detail/$personId")
                    },
                    onViewCombinedPhotos = { personIds ->
                        navController.navigate("person_detail/${personIds.joinToString(",")}")
                    }
                )
            }

            composable(
                route = "person_detail/{personIds}",
                arguments = listOf(navArgument("personIds") { type = NavType.StringType })
            ) {
                val viewModel: PersonDetailViewModel = hiltViewModel()
                PersonDetailScreen(
                    viewModel = viewModel,
                    onBackClick = { navController.popBackStack() },
                    onPhotoClick = { photoId ->
                        navController.navigate("lightbox/$photoId")
                    }
                )
            }

            composable(
                route = "lightbox/{photoId}",
                arguments = listOf(navArgument("photoId") { type = NavType.LongType })
            ) { backStackEntry ->
                val photoId = backStackEntry.arguments?.getLong("photoId") ?: 0L
                LightboxScreen(
                    initialPhotoId = photoId,
                    dao = dao,
                    onBackClick = { navController.popBackStack() }
                )
            }
        }
    }
}
