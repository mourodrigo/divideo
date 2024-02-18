//
//  Stuff.swift
//  divideo
//
//  Created by Rodrigo Bueno on 18/02/24.
//

import Foundation

// Enum to represent different screens
enum AppScreen {
    case welcome, videoSelection, videoEditing, progress
}

typealias CompletionClosure = ((Swift.Result<Void,Error>) ->())
