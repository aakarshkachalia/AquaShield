//
//  LearnView.swift
//  ClearWellNC
//

import SwiftData
import SwiftUI

struct LearnView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(TractStore.self) private var store
    @Environment(WellCareStore.self) private var wellCare
    @Query(sort: \LabResult.date, order: .reverse) private var results: [LabResult]
    @Query(sort: \SavedWell.savedAt, order: .reverse) private var savedWells: [SavedWell]

    private var context: WellCareContext {
        WellCareContext.make(results: results,
                             county: settings.effectiveCounty(savedWellCounty: savedWellCounty(savedWells, store: store)),
                             trends: CountyTrendData.loadBundled())
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.m) {
                    Text("What's in well water, where it comes from, who is most at risk, and how to fix it.")
                        .foregroundStyle(Color.textSecondary)
                        .padding(.bottom, Spacing.xs)
                    SectionHeader(title: "Contaminants")
                    ForEach(LearnLibrary.articles) { article in
                        NavigationLink {
                            LearnArticleView(article: article)
                        } label: {
                            LearnCardRow(article: article)
                        }
                        .buttonStyle(.plain)
                    }

                    SectionHeader(title: "Badges")
                    badgeStrip
                    WellCareSummaryCard(context: context)

                    SectionHeader(title: "About ClearWell")
                    NavigationLink {
                        HowItWorksView()
                    } label: {
                        NavigationCardLabel(title: Text("How It Works"),
                                            subtitle: Text("Where the data comes from and how the estimates are made."),
                                            systemImage: "info.circle.fill")
                    }
                    .buttonStyle(.plain)
                    Text(LearnArticle.footer)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, Spacing.s)
                }
                .padding(Spacing.l)
                .readableWidth()
            }
            .background(Color.appBackground)
            .navigationTitle("Learn")
        }
    }

    /// Every badge, earned or not, with icon + text (never color alone).
    private var badgeStrip: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: Spacing.m, alignment: .top)], spacing: Spacing.m) {
            ForEach(Badge.allCases) { badge in
                let earned = wellCare.state.isUnlocked(badge)
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Image(systemName: earned ? badge.symbol : "lock.fill")
                        .font(.title2)
                        .foregroundStyle(earned ? Color.brandPrimary : Color.statusUnknown)
                        .accessibilityHidden(true)
                    Text(badge.title).font(.headline)
                    Text(earned ? String(localized: "Earned") : badge.howToEarn)
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .card()
                .accessibilityElement(children: .combine)
                .accessibilityLabel(Text("\(badge.title), \(earned ? String(localized: "earned") : String(localized: "not earned yet. \(badge.howToEarn)"))"))
            }
        }
    }
}

private struct LearnCardRow: View {
    let article: LearnArticle

    var body: some View {
        NavigationCardLabel(title: Text(article.title),
                            subtitle: Text(article.contaminants.first?.info.plainSummary ?? ""),
                            systemImage: article.symbol)
    }
}

struct LearnArticleView: View {
    let article: LearnArticle

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.l) {
                limitsCard
                section("Where it comes from in NC wells", systemImage: "map", text: article.whereFrom)
                VStack(alignment: .leading, spacing: Spacing.m) {
                    sectionTitle("Health effects", systemImage: "heart.text.square")
                    labeled("Short term", article.shortTerm)
                    labeled("Long term", article.longTerm)
                }
                .card()
                section("Who is most at risk", systemImage: "person.2", text: article.mostAtRisk)
                Label {
                    Text(LearnArticle.symptomsNote)
                } icon: {
                    Image(systemName: "eye.slash").foregroundStyle(.tint)
                }
                .font(.subheadline.weight(.semibold))
                .card()
                treatments
                section("When to retest", systemImage: "calendar", text: article.retest)
                sources
                QuizView(questions: article.quiz, quizID: article.id)
                Text(LearnArticle.footer)
                    .font(.caption.weight(.semibold))
            }
            .padding(Spacing.l)
            .readableWidth()
        }
        .background(Color.appBackground)
        .navigationTitle(article.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var limitsCard: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            ForEach(article.contaminants) { id in
                let info = id.info
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(info.name).font(.headline)
                    Text(info.limitDescription)
                        .font(.subheadline)
                    Text(info.limitType == .health ? String(localized: "Health-based limit") : String(localized: "Cosmetic guideline (no health-based limit)"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .card()
    }

    private var treatments: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            sectionTitle("Treatment options", systemImage: "wrench.and.screwdriver")
            ForEach(article.treatments) { treatment in
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(treatment.name).font(.body.weight(.semibold))
                    Text(treatment.effectiveness).font(.subheadline)
                    if let note = treatment.note {
                        Text(note).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .accessibilityElement(children: .combine)
            }
            Text("Effectiveness is approximate and depends on your water and on maintenance. Choose products certified for the contaminant you need to remove.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .card()
    }

    private var sources: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            sectionTitle("Sources", systemImage: "books.vertical")
            ForEach(article.sources) { source in
                Link(destination: source.url) {
                    Label(source.title, systemImage: "arrow.up.right.square")
                        .frame(minHeight: 44, alignment: .leading)
                }
                .font(.subheadline)
            }
        }
        .card()
    }

    private func section(_ title: LocalizedStringKey, systemImage: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            sectionTitle(title, systemImage: systemImage)
            Text(text)
        }
        .card()
    }

    private func sectionTitle(_ title: LocalizedStringKey, systemImage: String) -> some View {
        Label {
            Text(title)
        } icon: {
            Image(systemName: systemImage).foregroundStyle(.tint)
        }
        .font(.headline)
        .accessibilityAddTraits(.isHeader)
    }

    private func labeled(_ label: LocalizedStringKey, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(label).font(.subheadline.weight(.semibold))
            Text(text)
        }
        .accessibilityElement(children: .combine)
    }
}

/// 3-question quiz scored on the device. Shows right/wrong with icon + text and the explanation.
struct QuizView: View {
    let questions: [QuizQuestion]
    /// Counts toward the Learner badge once every question is answered.
    var quizID: String?
    @State private var answers: [String: Int] = [:]

    private var correctCount: Int {
        questions.filter { answers[$0.id] == $0.correctIndex }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.l) {
            Label("Quick quiz", systemImage: "questionmark.circle")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            ForEach(Array(questions.enumerated()), id: \.element.id) { index, question in
                questionView(index: index, question: question)
            }
            if answers.count == questions.count {
                HStack {
                    Text("You got \(correctCount) of \(questions.count) right.")
                        .font(.headline)
                    Spacer()
                    Button("Try again") { answers.removeAll() }
                        .frame(minHeight: 44)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .card()
        .onChange(of: answers.count) { _, count in
            if count == questions.count, let quizID { WellCareStore.recordLearnQuiz(quizID) }
        }
    }

    private func questionView(index: Int, question: QuizQuestion) -> some View {
        let chosen = answers[question.id]
        return VStack(alignment: .leading, spacing: Spacing.s) {
            Text("\(index + 1). \(question.prompt)")
                .font(.body.weight(.semibold))
            ForEach(Array(question.options.enumerated()), id: \.offset) { optionIndex, option in
                Button {
                    if chosen == nil { answers[question.id] = optionIndex }
                } label: {
                    HStack {
                        Text(option).multilineTextAlignment(.leading)
                        Spacer()
                        if let chosen, optionIndex == question.correctIndex {
                            Label("Correct answer", systemImage: "checkmark.circle.fill")
                                .labelStyle(.iconOnly)
                                .foregroundStyle(Color.statusSafe)
                                .accessibilityHidden(chosen == optionIndex)
                        } else if chosen == optionIndex {
                            Label("Your answer", systemImage: "xmark.circle.fill")
                                .labelStyle(.iconOnly)
                                .foregroundStyle(Color.statusAbove)
                        }
                    }
                    .padding(Spacing.m)
                    .frame(minHeight: 44)
                    .background(optionFill(chosen: chosen, optionIndex: optionIndex, correct: question.correctIndex),
                                in: RoundedRectangle(cornerRadius: Radius.inner, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Radius.inner, style: .continuous)
                        .strokeBorder(optionBorder(chosen: chosen, optionIndex: optionIndex, correct: question.correctIndex)))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(chosen != nil)
                .accessibilityAddTraits(chosen == optionIndex ? .isSelected : [])
                .accessibilityValue(accessibilityValue(chosen: chosen, optionIndex: optionIndex, correct: question.correctIndex))
            }
            if let chosen {
                let right = chosen == question.correctIndex
                Label {
                    Text("\(right ? String(localized: "Correct.") : String(localized: "Not quite.")) \(question.explanation)")
                } icon: {
                    Image(systemName: right ? "checkmark.circle.fill" : "info.circle.fill")
                        .foregroundStyle(right ? Color.statusSafe : Color.statusWatch)
                }
                .font(.subheadline)
            }
        }
    }

    private func optionFill(chosen: Int?, optionIndex: Int, correct: Int) -> Color {
        guard let chosen else { return Color.primary.opacity(0.04) }
        if optionIndex == correct { return Color.statusSafe.opacity(0.12) }
        if optionIndex == chosen { return Color.statusAbove.opacity(0.12) }
        return Color.primary.opacity(0.04)
    }

    private func optionBorder(chosen: Int?, optionIndex: Int, correct: Int) -> Color {
        guard let chosen else { return Color.primary.opacity(0.08) }
        if optionIndex == correct { return Color.statusSafe.opacity(0.5) }
        if optionIndex == chosen { return Color.statusAbove.opacity(0.5) }
        return .clear
    }

    private func accessibilityValue(chosen: Int?, optionIndex: Int, correct: Int) -> Text {
        guard let chosen else { return Text("") }
        if optionIndex == correct { return Text("Correct answer") }
        if optionIndex == chosen { return Text("Your answer, incorrect") }
        return Text("")
    }
}
