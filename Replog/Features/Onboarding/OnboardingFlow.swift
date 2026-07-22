//
//  OnboardingFlow.swift
//  Replog
//
//  The tap-driven AI quiz. One question per step with a top progress bar + back,
//  a sticky CTA, an on-device "Building your plan" spinner, and a result screen.
//   - .firstRun: first launch; finishing marks onboarding done -> main app.
//   - .generatePlan: from Plans; finishing inserts a plan and reports it.
//

import SwiftUI
import SwiftData

struct OnboardingFlow: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Plan.order) private var plans: [Plan]
    @Query private var profiles: [UserProfile]

    var mode: OnboardingMode = .firstRun
    var onGenerated: ((Plan) -> Void)? = nil

    @Environment(\.exerciseCatalog) private var catalog
    @State private var vm = OnboardingViewModel()
    @State private var showReport = false
    @State private var showProgram = false
    @State private var previewRef: GeneratedWorkoutRef?
    @State private var didConfigure = false

    var body: some View {
        VStack(spacing: 0) {
            topBar
            ScrollView {
                stepContent
                    .padding(20)
                    .id(vm.current)
                    .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                            removal: .move(edge: .leading).combined(with: .opacity)))
            }
            if vm.showsPrimaryCTA { ctaBar }
        }
        .scrollDismissesKeyboard(.immediately)
        .hideKeyboardOnTap()
        .onAppear {
            guard !didConfigure else { return }
            didConfigure = true
            // Generating a plan from inside the app: the name is already known — skip that
            // step and reuse the stored name instead of asking again.
            if mode == .generatePlan {
                vm.skipName = true
                vm.answers.firstName = profiles.first?.name ?? ""
            }
        }
        .background(Color.bg.ignoresSafeArea())
        .sheet(isPresented: $showReport) {
            NavigationStack {
                CoachReportView(title: vm.generated?.headline ?? "Your Plan",
                                markdown: vm.reportMarkdown, showsDoneButton: true)
            }
        }
        .sheet(item: $previewRef) { ref in
            GeneratedWorkoutPreview(workout: ref.workout, catalog: catalog)
        }
        .sheet(isPresented: $showProgram) {
            if let program = vm.chosenProgram {
                NavigationStack {
                    ProgramDetailView(program: program, showsDoneButton: true)
                }
            }
        }
    }

    // MARK: Top bar (progress + back)

    private var topBar: some View {
        HStack(spacing: 12) {
            if vm.canGoBack {
                Button { withAnimation(.snappy) { vm.back() } } label: {
                    Image(systemName: "chevron.left").font(.system(size: 15, weight: .heavy))
                        .foregroundStyle(Color.text2).frame(width: 36, height: 36)
                        .background(Circle().fill(Color.surface2))
                }
                .buttonStyle(.plain)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.surface2)
                    Capsule().fill(Color.accent)
                        .frame(width: max(8, geo.size.width * vm.progress))
                }
            }
            .frame(height: 6)
        }
        .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 4)
    }

    // MARK: CTA

    private var ctaBar: some View {
        PrimaryButton(title: ctaTitle, systemImage: vm.current == .result ? "arrow.right" : nil) {
            primaryAction()
        }
        .opacity(vm.canProceed ? 1 : 0.5)
        .disabled(!vm.canProceed)
        .padding(.horizontal, 20).padding(.bottom, 12)
    }

    private var ctaTitle: String {
        switch vm.current {
        case .welcome: return "Get started"
        case .result: return mode == .firstRun ? "Start Replog" : "Use this plan"
        default: return vm.nextIsGenerating ? "Build my plan" : "Continue"
        }
    }

    private func primaryAction() {
        switch vm.current {
        case .result:
            finish()
        default:
            withAnimation(.snappy) { vm.advance() }
        }
    }

    // MARK: Steps

    @ViewBuilder
    private var stepContent: some View {
        switch vm.current {
        case .welcome:        welcomeStep
        case .name:           nameStep
        case .goal:           goalStep
        case .sport:          sportStep
        case .experience:     experienceStep
        case .gender:         genderStep
        case .age:            ageStep
        case .height:         heightStep
        case .weight:         weightStep
        case .days:           daysStep
        case .time:           timeStep
        case .injuries:       injuriesStep
        case .equipment:      equipmentStep
        case .equipmentTypes: equipmentTypesStep
        case .generating:     generatingStep
        case .result:         resultStep
        }
    }

    private var welcomeStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(LinearGradient(colors: [Color.accent, Color.accentPress], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 72, height: 72)
                .overlay(Image(systemName: "dumbbell.fill").font(.system(size: 30)).foregroundStyle(.white))
                .padding(.top, 40)
            Text("Welcome to Replog.").font(.screenTitle).foregroundStyle(Color.textPrimary)
            Text("Answer a few quick questions and your on-device AI coach will build a training plan tailored to you.")
                .font(.bodyText).foregroundStyle(Color.text2)
        }
    }

    private var nameStep: some View {
        OnboardingStepScaffold(eyebrow: "About you", question: "What's your name?",
                               caption: "We'll personalize your plan and coaching to you.") {
            nameField("First name", text: $vm.answers.firstName, content: .givenName)
        }
    }

    private func nameField(_ placeholder: String, text: Binding<String>,
                           content: UITextContentType?) -> some View {
        TextField(placeholder, text: text)
            .font(.rounded(17, .heavy))
            .textContentType(content)
            .autocorrectionDisabled()
            .submitLabel(.next)
            .padding(16)
            .background(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).fill(Color.surface))
            .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .strokeBorder(Color.border, lineWidth: 1))
    }

    private var heightStep: some View {
        OnboardingStepScaffold(eyebrow: "About you", question: "How tall are you?",
                               caption: "Helps us tailor the science to your body.") {
            sliderBlock(value: Binding(get: { Double(vm.answers.heightCm) },
                                       set: { vm.answers.heightCm = Int($0) }),
                        range: 140...210, unit: "cm")
        }
    }

    private var weightStep: some View {
        OnboardingStepScaffold(eyebrow: "About you", question: "What's your weight?",
                               caption: "Used to calibrate volume and starting loads.") {
            sliderBlock(value: $vm.answers.bodyWeightKg, range: 40...160, step: 1, unit: "kg")
        }
    }

    private var goalStep: some View {
        OnboardingStepScaffold(eyebrow: "Your goal", question: "What brings you to Replog?",
                               caption: "We'll tailor your plan to this.") {
            VStack(spacing: 10) {
                ForEach(Goal.allCases) { goal in
                    OptionCard(title: goal.displayName, subtitle: goalSubtitle(goal),
                               isSelected: vm.answers.goal == goal) { vm.answers.goal = goal }
                }
            }
        }
    }

    private var sportStep: some View {
        OnboardingStepScaffold(eyebrow: "Your sport", question: "Which sport?",
                               caption: "We'll prioritize the muscles it needs.") {
            VStack(spacing: 10) {
                ForEach(Sport.allCases) { sport in
                    OptionCard(title: sport.displayName, isSelected: vm.answers.sport == sport) {
                        vm.answers.sport = sport
                    }
                }
                if vm.answers.sport == .other {
                    nameField("Type your sport", text: $vm.answers.customSport, content: .none)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .animation(.snappy, value: vm.answers.sport)
        }
    }

    private var experienceStep: some View {
        OnboardingStepScaffold(eyebrow: "Experience", question: "How experienced are you?") {
            VStack(spacing: 10) {
                ForEach(Experience.allCases) { level in
                    OptionCard(title: level.displayName, isSelected: vm.answers.experience == level) {
                        vm.answers.experience = level
                    }
                }
            }
        }
    }

    private var genderStep: some View {
        OnboardingStepScaffold(eyebrow: "About you", question: "Gender") {
            VStack(spacing: 10) {
                ForEach(Gender.allCases) { gender in
                    OptionCard(title: gender.displayName, isSelected: vm.answers.gender == gender) {
                        vm.answers.gender = gender
                    }
                }
            }
        }
    }

    private var ageStep: some View {
        OnboardingStepScaffold(eyebrow: "About you", question: "How old are you?") {
            sliderBlock(value: Binding(get: { Double(vm.answers.age) },
                                       set: { vm.answers.age = Int($0) }),
                        range: 14...80, unit: "years")
        }
    }

    private var daysStep: some View {
        OnboardingStepScaffold(eyebrow: "Schedule", question: "Days per week?",
                               caption: "Pick anywhere from 2 to a full 7-day week.") {
            FlowLayout(spacing: 10) {
                ForEach(2...7, id: \.self) { d in
                    ChoiceChip(label: "\(d)", isSelected: vm.answers.daysPerWeek == d) {
                        vm.answers.daysPerWeek = d
                    }
                }
            }
        }
    }

    private var timeStep: some View {
        OnboardingStepScaffold(eyebrow: "Schedule", question: "Time per session?") {
            sliderBlock(value: Binding(get: { Double(vm.answers.minutesPerSession) },
                                       set: { vm.answers.minutesPerSession = Int($0) }),
                        range: 20...90, step: 5, unit: "min")
        }
    }

    private var injuriesStep: some View {
        OnboardingStepScaffold(eyebrow: "Limits", question: "Any injuries or limits?",
                               caption: "We'll work around these. Pick any that apply.") {
            VStack(spacing: 10) {
                OptionCard(title: "None", isSelected: vm.answers.injuries.isEmpty) {
                    vm.answers.injuries = []
                }
                ForEach(Injury.allCases) { injury in
                    OptionCard(title: injury.displayName, isSelected: vm.answers.injuries.contains(injury)) {
                        toggleInjury(injury)
                    }
                }
            }
        }
    }

    private var equipmentStep: some View {
        OnboardingStepScaffold(eyebrow: "Equipment", question: "Where do you train?") {
            VStack(spacing: 10) {
                ForEach(EquipmentAccess.allCases) { access in
                    OptionCard(title: access.displayName, isSelected: vm.answers.equipment == access) {
                        vm.answers.equipment = access
                        // Pre-select the equipment this access level implies; refined next step.
                        vm.answers.equipmentTypes = access.allowedEquipment
                            .intersection(Set(Equipment.selectable))
                    }
                }
            }
        }
    }

    private var equipmentTypesStep: some View {
        OnboardingStepScaffold(eyebrow: "Equipment", question: "What can you train with?",
                               caption: "Pick everything you have — your plan will only use these.") {
            FlowLayout(spacing: 10) {
                ForEach(Equipment.selectable) { eq in
                    ChoiceChip(label: eq.displayName, isSelected: vm.answers.equipmentTypes.contains(eq)) {
                        if vm.answers.equipmentTypes.contains(eq) {
                            vm.answers.equipmentTypes.remove(eq)
                        } else {
                            vm.answers.equipmentTypes.insert(eq)
                        }
                    }
                }
            }
            .onAppear {
                // Seed from the access level if the user hasn't chosen any types yet.
                if vm.answers.equipmentTypes.isEmpty {
                    vm.answers.equipmentTypes = vm.answers.equipment.allowedEquipment
                        .intersection(Set(Equipment.selectable))
                }
            }
        }
    }

    private var generatingStep: some View {
        VStack(spacing: 20) {
            Spacer(minLength: 80)
            ProgressView().controlSize(.large).tint(.accent)
            Text("Building your plan").font(.rounded(20, .black)).foregroundStyle(Color.textPrimary)
            Text("Your AI coach is tailoring your program on-device…")
                .font(.bodyText).foregroundStyle(Color.text2)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .task {
            // Feed any logged history into the planner (empty on first run), and run
            // generation while guaranteeing a minimum spinner time for a calm UX.
            let history = (try? context.fetch(FetchDescriptor<HistoryEntry>())) ?? []
            async let generation: Void = vm.generate(history: history)
            async let minimumDelay: Void = sleepQuietly(1.5)
            _ = await (generation, minimumDelay)
            withAnimation(.snappy) { vm.advance() }
        }
    }

    private func sleepQuietly(_ seconds: Double) async {
        try? await Task.sleep(for: .seconds(seconds))
    }

    private var resultStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Pill(text: "✨ Plan ready", style: .accentSoft)
            Text(vm.generated?.headline ?? "Your Plan").font(.screenTitle).foregroundStyle(Color.textPrimary)
            Text("\(vm.answers.daysPerWeek) days/week · ~\(vm.answers.minutesPerSession) min sessions")
                .font(.rounded(13, .semibold)).foregroundStyle(Color.text2)
            HStack(spacing: 8) {
                Pill(text: vm.answers.experience.displayName, style: .soft)
                Pill(text: vm.answers.equipment.displayName, style: .soft)
                Pill(text: vm.answers.goal.shortName, style: .soft)
            }

            if let program = vm.chosenProgram {
                Button { showProgram = true } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "book.pages.fill")
                            .font(.system(size: 16, weight: .bold)).foregroundStyle(Color.accent)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(program.name)
                                .font(.rounded(15, .heavy)).foregroundStyle(Color.textPrimary)
                                .lineLimit(2)
                            Text(programRationale(program))
                                .font(.rounded(12, .semibold)).foregroundStyle(Color.text2)
                                .lineLimit(2)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Color.text3)
                    }
                    .padding(14).cardSurface()
                }
                .buttonStyle(.plain)
            }

            if !vm.reportMarkdown.isEmpty {
                Button { showReport = true } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 16, weight: .bold)).foregroundStyle(Color.accent)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Read your coach's report")
                                .font(.rounded(15, .heavy)).foregroundStyle(Color.textPrimary)
                            Text(vm.usedAppleIntelligence
                                 ? "Tailored by Apple Intelligence · the science behind your plan"
                                 : "The science behind your plan")
                                .font(.rounded(12, .semibold)).foregroundStyle(Color.text2)
                                .lineLimit(1)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Color.text3)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                        .fill(Color.accentSoft))
                }
                .buttonStyle(.plain)
            }

            ForEach(Array((vm.generated?.workouts ?? []).enumerated()), id: \.offset) { _, workout in
                Button {
                    previewRef = GeneratedWorkoutRef(workout: workout)
                } label: {
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(workout.name).font(.cardTitle).foregroundStyle(Color.textPrimary)
                            Text("\(workout.items.count) exercises · \(workout.items.reduce(0) { $0 + $1.sets.count }) sets")
                                .font(.rounded(12, .semibold)).foregroundStyle(Color.text2)
                        }
                        Spacer()
                        Pill(text: workout.day.short, style: .accentSoft)
                        Image(systemName: "chevron.right").font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Color.text3)
                    }
                    .padding(14).cardSurface()
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: Helpers

    private func sliderBlock(value: Binding<Double>, range: ClosedRange<Double>,
                            step: Double = 1, unit: String) -> some View {
        VStack(spacing: 16) {
            Text("\(Int(value.wrappedValue))")
                .font(.rounded(60, .black)).foregroundStyle(Color.accent).tabularNumbers()
            Text(unit).eyebrow()
            Slider(value: value, in: range, step: step).tint(.accent)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 20)
    }

    private func toggleInjury(_ injury: Injury) {
        if vm.answers.injuries.contains(injury) { vm.answers.injuries.remove(injury) }
        else { vm.answers.injuries.insert(injury) }
    }

    /// The one-liner shown under the chosen program's name: the coach's justification when
    /// the model wrote one, else the program's own "who it's for".
    private func programRationale(_ program: WorkoutProgram) -> String {
        let j = vm.programJustification.trimmingCharacters(in: .whitespacesAndNewlines)
        return j.isEmpty ? program.whoIsItFor : j
    }

    private func goalSubtitle(_ g: Goal) -> String {
        switch g {
        case .buildMuscle: return "Hypertrophy & strength"
        case .loseWeight: return "Burn fat, stay lean"
        case .recomp: return "Recomposition"
        case .sport: return "Sport-specific focus"
        }
    }

    private func finish() {
        let generated = vm.generated ?? PlanGenerator().generate(vm.answers)
        let report = vm.reportMarkdown.isEmpty
            ? ReportComposer.fallbackMarkdown(answers: vm.answers, plan: generated)
            : vm.reportMarkdown
        let plan = PlanFactory.insert(generated, into: context,
                                      order: Reordering.nextOrder(after: plans),
                                      reportMarkdown: report)
        let profile = profiles.first ?? context.userProfile()
        if !vm.answers.fullName.isEmpty { profile.name = vm.answers.fullName }
        profile.goal = vm.answers.goal
        profile.onboardingDone = true
        // The quiz weight starts the bodyweight series (baseline for the Today card;
        // first periodic check-in due a week from now). Only when the series is empty —
        // regenerating a plan later must not overwrite a real scale reading.
        if context.latestBodyweight() == nil {
            context.logBodyweight(vm.answers.bodyWeightKg)
        }
        context.recomputeStreaks(profile: profile)
        try? context.save()
        if mode == .generatePlan {
            onGenerated?(plan)
            dismiss()
        }
    }
}
