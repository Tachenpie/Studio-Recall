//
//  ImageView.swift
//  Studio Recall
//
//  Created by True Jackie on 8/29/25.
//
import SwiftUI

struct ImageView: View {
    let image: Image
    var body: some View {
        image
            .resizable()
            .scaledToFit()
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .shadow(radius: 3)
    }
}
