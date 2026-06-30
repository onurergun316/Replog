//
//  PlansListView.swift
//  Replog
//
//  List of training programs (Plans) with two distinct create entry points:
//  Generate with AI (re-runs the quiz) and Build your own (empty plan).
//

import SwiftUI
import SwiftData

struct PlansListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Plan.order) private var plans: [Plan]
    @State private var path = NavigationPath()
    @State private var showGenerate = false

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Group {
                    header
                    createCards
                    if plans.isEmpty { emptyState }
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)

                ForEach(plans) { plan in
                    ZStack {
                        PlanCard(plan: plan)
                        NavigationLink(value: plan) { EmptyView() }.opacity(0) // hides the List chevron
                    }
                    .listRowInsets(EdgeInsets(top: 6, leading: 20, bottom: 6, trailing: 20))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) { delete(plan) } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Color.bg.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .planNavigationDestinations()
            .sheet(isPresented: $showGenerate) {
                OnboardingFlow(mode: .generatePlan) { path.append($0) }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Plans").font(.screenTitle).foregroundStyle(Color.textPrimary)
            Text("\(plans.count) \(plans.count == 1 ? "plan" : "plans") · swipe a plan to delete")
                .font(.rounded(13, .semibold)).foregroundStyle(Color.text2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func delete(_ plan: Plan) {
        context.delete(plan)
        try? context.save()
    }

    private var createCards: some View {
        HStack(spacing: 12) {
            CreateCard(icon: "sparkles", title: "Generate with AI",
                       subtitle: "Answer a few questions", filled: true) { showGenerate = true }
            CreateCard(icon: "plus", title: "Build your own",
                       subtitle: "Add exercises manually", filled: false) { buildYourOwn() }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "square.stack.3d.up").font(.system(size: 28)).foregroundStyle(Color.text3)
            Text("No plans yet").font(.cardTitle).foregroundStyle(Color.textPrimary)
            Text("Generate one with AI or build your own to get started.")
                .font(.rounded(13, .semibold)).foregroundStyle(Color.text3)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(.top, 40)
    }

    private func buildYourOwn() {
        let plan = PlanFactory.emptyPlan(into: context, order: plans.count)
        try? context.save()
        path.append(plan)
    }
}

// MARK: - Create card

private struct CreateCard: View {
    let icon: String
    let title: String
    let subtitle: String
    let filled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .black))
                    .foregroundStyle(filled ? .white : Color.accent)
                    .frame(width: 34, height: 34)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(filled ? .white.opacity(0.22) : Color.accentSoft))
                Spacer(minLength: 8)
                Text(title).font(.rounded(15, .heavy))
                    .foregroundStyle(filled ? .white : Color.textPrimary)
                Text(subtitle).font(.rounded(12, .semibold))
                    .foregroundStyle(filled ? .white.opacity(0.85) : Color.text2)
            }
            .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .fill(filled
                          ? AnyShapeStyle(LinearGradient(colors: [Color.accent, Color.accentPress],
                                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                          : AnyShapeStyle(Color.surface))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .strokeBorder(Color.border, lineWidth: filled ? 0 : 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Plan card

private struct PlanCard: View {
    let plan: Plan

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                HStack(spacing: 8) {
                    Circle().fill(Color(hex: plan.colorHex)).frame(width: 9, height: 9)
                    Text(plan.name).font(.cardTitle).foregroundStyle(Color.textPrimary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.text3)
            }
            Text("\(plan.workouts.count) workouts · \(plan.exerciseCount) exercises")
                .font(.rounded(13, .semibold)).foregroundStyle(Color.text2)
            HStack(spacing: 6) {
                ForEach(plan.scheduledDays) { day in
                    Pill(text: day.short, style: .accentSoft)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }
}
