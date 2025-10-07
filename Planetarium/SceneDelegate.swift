//
//  SceneDelegate.swift
//  Planetarium
//
//  Created by Codex on 2025-03-17.
//

import UIKit
import StarryNight

class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else {
            return
        }

        let window = UIWindow(windowScene: windowScene)
        let starManager = try! StarManager()

        let metalViewController = MetalViewController(starManager: starManager)
        metalViewController.view.backgroundColor = .systemBackground
        metalViewController.title = "Metal"

        let navigationController = UINavigationController(rootViewController: metalViewController)
        navigationController.tabBarItem = UITabBarItem(title: "Metal", image: UIImage(systemName: "move.3d"), tag: 0)

        window.rootViewController = navigationController
        self.window = window
        window.makeKeyAndVisible()
    }
}

