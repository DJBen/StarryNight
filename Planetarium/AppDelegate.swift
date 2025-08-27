//
//  AppDelegate.swift
//  Planetarium
//
//  Created by Sihao Lu on 8/3/25.
//

import UIKit
import StarryNight

@main
class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // Create window
        window = UIWindow(frame: UIScreen.main.bounds)

        let starManager = try! StarManager()

        // Create view controllers
        let planetariumViewController = PlanetariumViewController(starManager: starManager)
        planetariumViewController.tabBarItem = UITabBarItem(title: "Planetarium", image: UIImage(systemName: "star.fill"), tag: 0)
        
        let settingsViewController = MetalViewController()
        settingsViewController.view.backgroundColor = .systemBackground
        settingsViewController.title = "Metal"
        settingsViewController.tabBarItem = UITabBarItem(title: "Metal", image: UIImage(systemName: "move.3d"), tag: 1)
        
        // Create tab bar controller
        let tabBarController = UITabBarController()
        tabBarController.viewControllers = [planetariumViewController, settingsViewController]
        
        // Set root view controller
        window?.rootViewController = tabBarController
        
        // Make window visible
        window?.makeKeyAndVisible()
        
        return true
    }

    func applicationWillResignActive(_ application: UIApplication) {
        // Sent when the application is about to move from active to inactive state. This can occur for certain types of temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the application and it begins the transition to the background state.
        // Use this method to pause ongoing tasks, disable timers, and invalidate graphics rendering callbacks. Games should use this method to pause the game.
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        // Use this method to release shared resources, save user data, invalidate timers, and store enough application state information to restore your application to its current state in case it is terminated later.
    }

    func applicationWillEnterForeground(_ application: UIApplication) {
        // Called as part of the transition from the background to the active state; here you can undo many of the changes made on entering the background.
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        // Restart any tasks that were paused (or not yet started) while the application was inactive. If the application was previously in the background, optionally refresh the user interface.
    }
}

