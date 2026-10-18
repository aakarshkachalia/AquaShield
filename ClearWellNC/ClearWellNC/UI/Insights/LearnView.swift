//
//  LearnView.swift
//  ClearWellNC
//

import SwiftUI

struct LearnView: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("What's in well water, where it comes from, who is most at risk, and how to fix it.")
                        .foregroundStyle(.secondary)
                    ForEach(LearnLibrary.articles) { article in
                        NavigationLink {
                            LearnArticleView(article: article)
                        } label: {
                            LearnCardRow(article: article)
                        }
                        .buttonStyle(.plain)
                    }
                    Text(LearnArticle.footer)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.top, 8)
                }
                .padding()
                .readableWidth()
            }
            .background(Color.appBackground)
            .navigationTitle("Learn")
        }
    }
}

private struct LearnCardRow: View {
    let article: LearnArticle

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: article.symbol)
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 32)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(article.title)
                    .font(.headline)
                Text(article.contaminants.first?.info.plainSummary ?? "")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .contentShape(Rectangle())
        .card()
        .accessibilityElement(children: .combine)
    }
}

struct LearnArticleView: View {
    let article: LearnArticle

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                limitsCard
                section("Where it comes from in NC wells", systemImage: "map", text: article.whereFrom)
                VStack(alignment: .leading, spacing: 10) {
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
                QuizView(questions: article.quiz)
                Text(LearnArticle.footer)
                    .font(.footnote.weight(.semibold))
            }
            .padding()
            .readableWidth()
        }
        .background(Color.appBackground)
        .navigationTitle(article.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var limitsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(article.contaminants) { id in
                let info = id.info
                VStack(alignment: .leading, spacing: 2) {
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
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Treatment options", systemImage: "wrench.and.screwdriver")
            ForEach(article.treatments) { treatment in
                VStack(alignment: .leading, spacing: 2) {
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
        VStack(alignment: .leading, spacing: 4) {
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
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle(title, systemImage: systemImage)
            Text(text)
        }
        .card()
    }

    private func sectionTitle(_ title: LocalizedStringKey, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.headline)
            .accessibilityAddTraits(.isHeader)
    }

    private func labeled(_ label: LocalizedStringKey, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.subheadline.weight(.semibold))
            Text(text)
        }
        .accessibilityElement(children: .combine)
    }
}

/// 3-question quiz scored on the device. Shows right/wrong with icon + text and the explanation.
struct QuizView: View {
    let questions: [QuizQuestion]
    @State private var answers: [String: Int] = [:]

    private var correctCount: Int {
        questions.filter { answers[$0.id] == $0.correctIndex }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
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
    }

    private func questionView(index: Int, question: QuizQuestion) -> some View {
        let chosen = answers[question.id]
        return VStack(alignment: .leading, spacing: 8) {
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
                                .foregroundStyle(.tint)
                                .accessibilityHidden(chosen == optionIndex)
                        } else if chosen == optionIndex {
                            Label("Your answer", systemImage: "xmark.circle.fill")
                                .labelStyle(.iconOnly)
                                .foregroundStyle(RiskLevel.high.color)
                        }
                    }
                    .padding(12)
                    .frame(minHeight: 44)
                    .background(Color.primary.opacity(chosen == optionIndex ? 0.1 : 0.04),
                                in: RoundedRectangle(cornerRadius: 10, style: .continuous))
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
                        .foregroundStyle(right ? Color.accentColor : RiskLevel.elevated.color)
                }
                .font(.subheadline)
            }
        }
    }

    private func accessibilityValue(chosen: Int?, optionIndex: Int, correct: Int) -> Text {
        guard let chosen else { return Text("") }
        if optionIndex == correct { return Text("Correct answer") }
        if optionIndex == chosen { return Text("Your answer, incorrect") }
        return Text("")
    }
}
