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
                    Text("Learn").font(M.Font.screenTitle).accessibilityAddTraits(.isHeader)
                    let ranked = rankedArticles
                    if let top = ranked.first {
                        NavigationLink { LearnArticleView(article: top.article) } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("MATCHES YOUR RESULT").font(M.Font.label).tracking(0.8).foregroundStyle(M.Colors.overText)
                                Text(top.article.title).font(.system(.title, weight: .light))
                                Text("Where it comes from · how to remove it · 4 min")
                                    .font(M.Font.small).foregroundStyle(M.Colors.muted)
                            }
                            .padding(16)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(M.Colors.surface)
                            .overlay(alignment: .leading) { Rectangle().fill(M.Colors.over).frame(width: 3) }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("learn.featured")
                    }
                    if ranked.count > 1 {
                        M.SectionHeader(title: String(localized: "In your water"),
                                        note: results.first.map { String(localized: "from \($0.date.formatted(.dateTime.month(.abbreviated).day())) test") })
                            .padding(.top, 8)
                        VStack(spacing: 0) {
                            ForEach(ranked.dropFirst(), id: \.article.id) { entry in
                                NavigationLink { LearnArticleView(article: entry.article) } label: {
                                    HStack {
                                        Text(entry.article.title).font(M.Font.row)
                                        Spacer()
                                        HStack(spacing: 5) { M.Dot(color: entry.zone.color, size: 6); Text(entry.zone.label) }
                                            .font(M.Font.label).foregroundStyle(entry.zone.textColor)
                                        Image(systemName: "chevron.right").font(.system(.caption, weight: .light))
                                            .foregroundStyle(M.Colors.muted)
                                    }
                                    .frame(minHeight: 46)
                                    .overlay(alignment: .bottom) { M.Rule(color: M.Colors.hairline) }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    // Everything stays browsable; city users see city topics first when there are no results.
                    let shown = Set(ranked.map(\.article.id))
                    let rest = LearnLibrary.articles.filter { !shown.contains($0.id) }
                    let featured = settings.waterSource.showsWellCare || !ranked.isEmpty ? rest
                        : rest.filter { $0.contaminants.contains(where: Self.cityTopics.contains) }
                    let more = rest.filter { article in !featured.contains { $0.id == article.id } }
                    M.SectionHeader(title: ranked.isEmpty
                                    ? (settings.waterSource.showsWellCare ? String(localized: "Contaminants") : String(localized: "For city water"))
                                    : String(localized: "More topics"))
                        .padding(.top, 8)
                    ForEach(featured + more) { articleLink($0) }

                    SectionHeader(title: "Badges")
                    badgeStrip
                    WellCareSummaryCard(context: context)

                    if settings.waterSource.showsWellCare {
                        SectionHeader(title: "About \(AppName.display)")
                        NavigationLink {
                            HowItWorksView()
                        } label: {
                            NavigationCardLabel(title: Text("How It Works"),
                                                subtitle: Text("Where the data comes from and how the estimates are made."),
                                                systemImage: "info.circle.fill")
                        }
                        .buttonStyle(.plain)
                    }
                    Text(LearnArticle.footer)
                        .font(.caption)
                        .foregroundStyle(M.Colors.muted)
                        .padding(.top, Spacing.s)
                }
                .padding(Spacing.l)
                .readableWidth()
            }
            .modernistScreen()
            .toolbarVisibility(.hidden, for: .navigationBar)
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
                    Text(badge.title).font(M.Font.section)
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

extension LearnView {
    /// Articles for contaminants in your latest test, worst result first.
    var rankedArticles: [(article: LearnArticle, zone: M.Zone)] {
        guard let latest = results.first else { return [] }
        var seen: Set<String> = []
        return latest.displayInterpretations
            .compactMap { i -> (LearnArticle, M.Zone, Double)? in
                guard let article = LearnLibrary.article(for: i.id) else { return nil }
                let ratio = (i.percentOfLimit ?? (i.tier == .above ? 100 : 0)) / 100
                return (article, M.Zone(ratio: ratio), ratio)
            }
            .sorted { $0.2 > $1.2 }
            .filter { seen.insert($0.0.id).inserted }
            .map { ($0.0, $0.1) }
    }

    static let cityTopics: Set<ContaminantID> = [.lead, .copper, .pfoa, .pfos, .genx, .totalColiform, .eColi]

    func articleLink(_ article: LearnArticle) -> some View {
        NavigationLink {
            LearnArticleView(article: article)
        } label: {
            LearnCardRow(article: article)
        }
        .buttonStyle(.plain)
    }
}

struct LearnArticleView: View {
    let article: LearnArticle

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.l) {
                hero
                limitsCard
                keyPoint("map", String(localized: "Where it comes from"), article.whereFrom)
                VStack(alignment: .leading, spacing: DS.Space.m) {
                    Text("Where it can affect the body").font(DS.Typography.headline).foregroundStyle(DS.Colors.textPrimary)
                    BodyAreaGrid(areas: article.contaminants.flatMap(BodyArea.areas(for:)).uniqued())
                    DS.InfoCard(systemImage: "heart.text.square", title: String(localized: "Health effects"),
                                message: QuestText.firstSentences(article.shortTerm, max: 1),
                                learnMore: article.shortTerm + "\n\n" + article.longTerm)
                }
                .dsCard()
                keyPoint("person.2", String(localized: "Who is most at risk"), article.mostAtRisk)
                DS.InfoCard(systemImage: "eye.slash", title: LearnArticle.symptomsNote)
                treatments
                keyPoint("calendar", String(localized: "When to retest"), article.retest)
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

    /// Leads with the answer: what it is, in one or two sentences.
    private var hero: some View {
        HStack(alignment: .top, spacing: Spacing.m) {
            DS.IconBadge(systemImage: article.contaminants.first.map(DS.Icon.contaminant) ?? article.symbol)
            Text(article.contaminants.first?.info.plainSummary ?? "")
                .font(DS.Typography.body)
                .foregroundStyle(DS.Colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// First sentence on the card; the rest behind "Learn why".
    private func keyPoint(_ symbol: String, _ title: String, _ text: String) -> some View {
        let first = QuestText.firstSentences(text, max: 1)
        let rest = text.hasPrefix(first) ? text.dropFirst(first.count).trimmingCharacters(in: .whitespaces) : ""
        return DS.InfoCard(systemImage: symbol, title: title, message: first, learnMore: rest.isEmpty ? nil : rest)
    }

    private var limitsCard: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            ForEach(article.contaminants) { id in
                let info = id.info
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(info.name).font(M.Font.section)
                    Text(info.limitDescription)
                        .font(.subheadline)
                    Text(info.limitType == .health ? String(localized: "Health-based limit") : String(localized: "Cosmetic guideline (no health-based limit)"))
                        .font(.caption)
                        .foregroundStyle(M.Colors.muted)
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
                    Text(treatment.name).font(M.Font.section)
                    Text(treatment.effectiveness).font(.subheadline)
                    if let note = treatment.note {
                        Text(note).font(.caption).foregroundStyle(M.Colors.muted)
                    }
                }
                .accessibilityElement(children: .combine)
            }
            Text("Effectiveness is approximate and depends on your water and on maintenance. Choose products certified for the contaminant you need to remove.")
                .font(.caption)
                .foregroundStyle(M.Colors.muted)
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
        .font(M.Font.section)
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

/// A Learn quiz in progress: answers plus the question on screen. Step `questions.count` is the score.
nonisolated struct QuizDraft: Codable, Sendable, Equatable {
    var answers: [String: Int] = [:]
    var flow = StepFlow(root: 0)

    static func key(quizID: String) -> DraftKey<QuizDraft> { DraftKey(name: "quiz.\(quizID)", schemaVersion: 1) }
}

/// Quiz scored on the device, one question at a time with Back and progress. Shows right/wrong with
/// icon + text and the explanation. Answers are saved as you go.
struct QuizView: View {
    let questions: [QuizQuestion]
    /// Counts toward the Learner badge once every question is answered. Also keys the saved answers.
    var quizID: String?
    @Environment(AppSettings.self) private var settings
    @State private var draft = QuizDraft()
    @State private var loaded = false

    private var answers: [String: Int] { draft.answers }
    private var order: [Int] { Array(0...questions.count) }

    private var correctCount: Int {
        questions.filter { answers[$0.id] == $0.correctIndex }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.l) {
            Label("Quick quiz", systemImage: "questionmark.circle")
                .font(M.Font.section)
                .accessibilityAddTraits(.isHeader)
            let step = draft.flow.current
            if questions.indices.contains(step) {
                StepProgressBar(progress: StepProgress(position: step + 1, total: questions.count,
                                                       label: String(localized: "Question \(step + 1) of \(questions.count)")))
                questionView(index: step, question: questions[step])
            } else {
                Text("You got \(correctCount) of \(questions.count) right.")
                    .font(M.Font.section)
            }
            HStack(spacing: Spacing.m) {
                if draft.flow.canGoBack {
                    SecondaryButton(title: "Back", systemImage: "chevron.left") { draft.flow.back() }
                }
                if questions.indices.contains(step) {
                    if answers[questions[step].id] != nil {
                        PrimaryButton(title: step + 1 == questions.count ? "See my score" : "Next") {
                            draft.flow.advance(in: order)
                        }
                    }
                } else {
                    PrimaryButton(title: "Try again", systemImage: "arrow.counterclockwise") {
                        draft = QuizDraft()
                    }
                }
            }
        }
        .card()
        .onAppear(perform: load)
        .onChange(of: draft) { _, newValue in
            guard loaded, let quizID else { return }
            if newValue == QuizDraft() {
                settings.drafts.discard(QuizDraft.key(quizID: quizID))
            } else {
                settings.drafts.save(newValue, for: QuizDraft.key(quizID: quizID))
            }
        }
        .onChange(of: answers.count) { _, count in
            if count == questions.count, let quizID { WellCareStore.recordLearnQuiz(quizID) }
        }
    }

    /// Picks up where the reader left off. Inline in an article, so there is no separate prompt.
    private func load() {
        guard !loaded else { return }
        loaded = true
        guard let quizID else { return }
        if let saved = settings.drafts.load(QuizDraft.key(quizID: quizID)), saved.payload.flow.isValid(in: order) {
            draft = saved.payload
        } else {
            settings.drafts.discard(QuizDraft.key(quizID: quizID))
        }
    }

    private func questionView(index: Int, question: QuizQuestion) -> some View {
        let chosen = answers[question.id]
        return VStack(alignment: .leading, spacing: Spacing.s) {
            Text("\(index + 1). \(question.prompt)")
                .font(M.Font.section)
            ForEach(Array(question.options.enumerated()), id: \.offset) { optionIndex, option in
                Button {
                    if chosen == nil { draft.answers[question.id] = optionIndex }
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
        guard let chosen else { return M.Colors.ink.opacity(0.04) }
        if optionIndex == correct { return Color.statusSafe.opacity(0.12) }
        if optionIndex == chosen { return Color.statusAbove.opacity(0.12) }
        return M.Colors.ink.opacity(0.04)
    }

    private func optionBorder(chosen: Int?, optionIndex: Int, correct: Int) -> Color {
        guard let chosen else { return M.Colors.ink.opacity(0.08) }
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
