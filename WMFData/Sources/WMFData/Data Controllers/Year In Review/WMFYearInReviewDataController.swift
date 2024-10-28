import Foundation
import CoreData

public class WMFYearInReviewDataController {

    public let coreDataStore: WMFCoreDataStore
    private let userDefaultsStore: WMFKeyValueStore?
    private let developerSettingsDataController: WMFDeveloperSettingsDataControlling

    public let targetConfigYearID = "2024.1"

    private let service = WMFDataEnvironment.current.mediaWikiService

    struct FeatureAnnouncementStatus: Codable {
        var hasPresentedYiRFeatureAnnouncementModal: Bool
        static var `default`: FeatureAnnouncementStatus {
            return FeatureAnnouncementStatus(hasPresentedYiRFeatureAnnouncementModal: false)
        }
    }

    public init(coreDataStore: WMFCoreDataStore? = WMFDataEnvironment.current.coreDataStore, userDefaultsStore: WMFKeyValueStore? = WMFDataEnvironment.current.userDefaultsStore, developerSettingsDataController: WMFDeveloperSettingsDataControlling = WMFDeveloperSettingsDataController.shared) throws {

        guard let coreDataStore else {
            throw WMFDataControllerError.coreDataStoreUnavailable
        }
        self.coreDataStore = coreDataStore
        self.userDefaultsStore = userDefaultsStore
        self.developerSettingsDataController = developerSettingsDataController
    }

    // MARK: - Feature Announcement

    private var featureAnnouncementStatus: FeatureAnnouncementStatus {
        return (try? userDefaultsStore?.load(key: WMFUserDefaultsKey.yearInReviewFeatureAnnouncement.rawValue)) ?? FeatureAnnouncementStatus.default
    }

    public var hasPresentedYiRFeatureAnnouncementModel: Bool {
        get {
            return featureAnnouncementStatus.hasPresentedYiRFeatureAnnouncementModal
        } set {
            var currentAnnouncementStatus = featureAnnouncementStatus
            currentAnnouncementStatus.hasPresentedYiRFeatureAnnouncementModal = newValue
            try? userDefaultsStore?.save(key: WMFUserDefaultsKey.yearInReviewFeatureAnnouncement.rawValue, value: currentAnnouncementStatus)
        }
    }

    func isAnnouncementActive() -> Bool {
        let expiryDate: Date? = {
            var expiryDateComponents = DateComponents()
            expiryDateComponents.year = 2025
            expiryDateComponents.month = 3
            expiryDateComponents.day = 1
            return Calendar.current.date(from: expiryDateComponents)
        }()

        guard let expiryDate else {
            return false
        }
        let currentDate = Date()
        return currentDate <= expiryDate
    }

    public func shouldShowYearInReviewFeatureAnnouncement(primaryAppLanguageProject: WMFProject?) -> Bool {

        guard isAnnouncementActive() else {
            return false
        }


        guard shouldShowYearInReviewEntryPoint(countryCode: Locale.current.region?.identifier, primaryAppLanguageProject: primaryAppLanguageProject) else {
            return false
        }

        guard !hasPresentedYiRFeatureAnnouncementModel else {
            return false
        }

        return true
    }

    func shouldPopulateYearInReviewReportData(countryCode: String?, primaryAppLanguageProject: WMFProject?) -> Bool {
        
        // Check local developer settings feature flag
        guard developerSettingsDataController.enableYearInReview else {
            return false
        }

        guard let iosFeatureConfig = developerSettingsDataController.loadFeatureConfig()?.ios.first,
              let yirConfig = iosFeatureConfig.yir(yearID: targetConfigYearID) else {
            return false
        }
        
        guard let countryCode,
              let primaryAppLanguageProject else {
            return false
        }
        
        // Check remote feature disable switch
        guard yirConfig.isEnabled else {
            return false
        }
        
        // Check remote valid country codes
        let uppercaseConfigCountryCodes = yirConfig.countryCodes.map { $0.uppercased() }
        guard uppercaseConfigCountryCodes.contains(countryCode.uppercased()) else {
            return false
        }
        
        // Check remote valid primary app language wikis
        let uppercaseConfigPrimaryAppLanguageCodes = yirConfig.primaryAppLanguageCodes.map { $0.uppercased() }

        guard let languageCode = primaryAppLanguageProject.languageCode,
              uppercaseConfigPrimaryAppLanguageCodes.contains(languageCode.uppercased()) else {
            return false
        }
        
        return true
    }
    
    public func shouldShowYearInReviewEntryPoint(countryCode: String?, primaryAppLanguageProject: WMFProject?) -> Bool {
        assert(Thread.isMainThread, "This method must be called from the main thread in order to keep it synchronous")
        
        // Check local developer settings feature flag
        guard developerSettingsDataController.enableYearInReview else {
            return false
        }
        
        guard let countryCode,
              let primaryAppLanguageProject else {
            return false
        }
        
        guard let iosFeatureConfig = developerSettingsDataController.loadFeatureConfig()?.ios.first,
              let yirConfig = iosFeatureConfig.yir(yearID: targetConfigYearID) else {
            return false
        }
        
        // Check remote feature disable switch
        guard yirConfig.isEnabled else {
            return false
        }
        
        
        // Check remote valid country codes
        let uppercaseConfigCountryCodes = yirConfig.countryCodes.map { $0.uppercased() }
        guard uppercaseConfigCountryCodes.contains(countryCode.uppercased()) else {
            return false
        }
        
        // Check remote valid primary app language wikis
        let uppercaseConfigPrimaryAppLanguageCodes = yirConfig.primaryAppLanguageCodes.map { $0.uppercased() }
        guard let languageCode = primaryAppLanguageProject.languageCode,
              uppercaseConfigPrimaryAppLanguageCodes.contains(languageCode.uppercased()) else {
            return false
        }
        
        // Check persisted year in review report. Year in Review entry point should display if one or more personalized slides are set to display and slide is not disabled in remote config
        guard let yirReport = try? fetchYearInReviewReport(forYear: 2024) else {
            return false
        }
        
        var personalizedSlideCount = 0

        for slide in yirReport.slides {
            switch slide.id {
            case .readCount:
                if yirConfig.personalizedSlides.readCount.isEnabled,
                   slide.display == true {
                    personalizedSlideCount += 1
                }
            case .editCount:
                if yirConfig.personalizedSlides.editCount.isEnabled,
                   slide.display == true {
                    personalizedSlideCount += 1
                }
            }
        }
        
        return personalizedSlideCount >= 1
    }
    
    @discardableResult
    public func populateYearInReviewReportData(for year: Int, countryCode: String, primaryAppLanguageProject: WMFProject?, username: String?) async throws -> WMFYearInReviewReport? {
        
        guard shouldPopulateYearInReviewReportData(countryCode: countryCode, primaryAppLanguageProject: primaryAppLanguageProject) else {
            return nil
        }
        
        let backgroundContext = try coreDataStore.newBackgroundContext
        
        let result: (report: CDYearInReviewReport, needsReadingPopulation: Bool, needsEditingPopulation: Bool)? = try await backgroundContext.perform { [weak self] in
            return try self?.getYearInReviewReportAndDataPopulationFlags(year: year, backgroundContext: backgroundContext, project: primaryAppLanguageProject, username: username)
        }
        
        guard let result else {
            return nil
        }
        
        let report = result.report
        
        if result.needsReadingPopulation == true {
            try await backgroundContext.perform { [weak self] in
                try self?.populateReadingSlide(report: report, backgroundContext: backgroundContext)
            }
        }
        
        if result.needsEditingPopulation == true {
            if let username {
                let edits = try await fetchEditCount(username: username, project: primaryAppLanguageProject)
                try await backgroundContext.perform { [weak self] in
                    try self?.populateEditingSlide(edits: edits, report: report, backgroundContext: backgroundContext)
                }
            }
        }
        
        return WMFYearInReviewReport(cdReport: report)
    }
    
    private func getYearInReviewReportAndDataPopulationFlags(year: Int, backgroundContext: NSManagedObjectContext, project: WMFProject?, username: String?) throws -> (report: CDYearInReviewReport, needsReadingPopulation: Bool, needsEditingPopulation: Bool)? {
        let predicate = NSPredicate(format: "year == %d", year)
        let cdReport = try self.coreDataStore.fetchOrCreate(entityType: CDYearInReviewReport.self, predicate: predicate, in: backgroundContext)
        
        guard let cdReport else {
            return nil
        }
        
        cdReport.year = Int32(year)
        if (cdReport.slides?.count ?? 0) == 0 {
            cdReport.slides = try self.initialSlides(year: year, moc: backgroundContext) as NSSet
        }
        
        try self.coreDataStore.saveIfNeeded(moc: backgroundContext)
        
        guard let iosFeatureConfig = developerSettingsDataController.loadFeatureConfig()?.ios.first,
              let yirConfig = iosFeatureConfig.yir(yearID: targetConfigYearID) else {
            return nil
        }

        guard let cdSlides = cdReport.slides as? Set<CDYearInReviewSlide> else {
            return nil
        }
        
        var needsReadingPopulation = false
        var needsEditingPopulation = false
        
        for slide in cdSlides {
            switch slide.id {
                
            case WMFYearInReviewPersonalizedSlideID.readCount.rawValue:
                if slide.evaluated == false && yirConfig.personalizedSlides.readCount.isEnabled {
                    needsReadingPopulation = true
                }
                
            case WMFYearInReviewPersonalizedSlideID.editCount.rawValue:
                if slide.evaluated == false && yirConfig.personalizedSlides.editCount.isEnabled && username != nil {
                    needsEditingPopulation = true
                }
            default:
                debugPrint("Unrecognized Slide ID")
            }
        }
        
        return (report: cdReport, needsReadingPopulation: needsReadingPopulation, needsEditingPopulation: needsEditingPopulation)
    }
    
    func initialSlides(year: Int, moc: NSManagedObjectContext) throws -> Set<CDYearInReviewSlide> {
        var results = Set<CDYearInReviewSlide>()
        if year == 2024 {
            
            let readCountSlide = try coreDataStore.create(entityType: CDYearInReviewSlide.self, in: moc)
            readCountSlide.year = 2024
            readCountSlide.id = WMFYearInReviewPersonalizedSlideID.readCount.rawValue
            readCountSlide.evaluated = false
            readCountSlide.display = false
            readCountSlide.data = nil
            results.insert(readCountSlide)
            
            let editCountSlide = try coreDataStore.create(entityType: CDYearInReviewSlide.self, in: moc)
            editCountSlide.year = 2024
            editCountSlide.id = WMFYearInReviewPersonalizedSlideID.editCount.rawValue
            editCountSlide.evaluated = false
            editCountSlide.display = false
            editCountSlide.data = nil
            results.insert(editCountSlide)
        }
        
        return results
    }
    
    private func populateReadingSlide(report: CDYearInReviewReport, backgroundContext: NSManagedObjectContext) throws {
        
        guard let iosFeatureConfig = developerSettingsDataController.loadFeatureConfig()?.ios.first,
              let yirConfig = iosFeatureConfig.yir(yearID: targetConfigYearID) else {
            return
        }
        
        guard let dataPopulationStartDate = yirConfig.dataPopulationStartDate,
              let dataPopulationEndDate = yirConfig.dataPopulationEndDate else {
            return
        }
        
        let pageViewsDataController = try WMFPageViewsDataController(coreDataStore: coreDataStore)
        let pageViewCounts = try pageViewsDataController.fetchPageViewCounts(startDate: dataPopulationStartDate, endDate: dataPopulationEndDate, moc: backgroundContext)
        
        guard let slides = report.slides as? Set<CDYearInReviewSlide> else {
            return
        }
        
        for slide in slides {
            
            guard let slideID = slide.id else {
                continue
            }
            
            switch slideID {
            case WMFYearInReviewPersonalizedSlideID.readCount.rawValue:
                let encoder = JSONEncoder()
                slide.data = try encoder.encode(pageViewCounts.count)
                
                if pageViewCounts.count > 5 {
                    slide.display = true
                }
                
                slide.evaluated = true
            default:
                break
            }
        }
        
        try coreDataStore.saveIfNeeded(moc: backgroundContext)
    }
    
    private func fetchEditCount(username: String, project: WMFProject?) async throws -> Int {
        
        guard let iosFeatureConfig = developerSettingsDataController.loadFeatureConfig()?.ios.first,
              let yirConfig = iosFeatureConfig.yir(yearID: targetConfigYearID) else {
            throw WMFYearInReviewDataControllerError.missingRemoteConfig
        }
        
        let dataPopulationStartDateString = yirConfig.dataPopulationStartDateString
        let dataPopulationEndDateString = yirConfig.dataPopulationEndDateString
        
        let (edits, _) = try await fetchUserContributionsCount(username: username, project: project, startDate: dataPopulationStartDateString, endDate: dataPopulationEndDateString)
        
        return edits
    }
    
    private func populateEditingSlide(edits: Int, report: CDYearInReviewReport, backgroundContext: NSManagedObjectContext) throws {
        
        guard let slides = report.slides as? Set<CDYearInReviewSlide> else {
            return
        }

        for slide in slides {
            
            guard let slideID = slide.id else {
                continue
            }
            
            switch slideID {
            case WMFYearInReviewPersonalizedSlideID.editCount.rawValue:
                let encoder = JSONEncoder()
                slide.data = try encoder.encode(edits)
                
                if edits > 0 {
                    slide.display = true
                }
                
                slide.evaluated = true
            default:
                break
            }
        }
        
        try coreDataStore.saveIfNeeded(moc: backgroundContext)
    }
    
    public func saveYearInReviewReport(_ report: WMFYearInReviewReport) async throws {
        let backgroundContext = try coreDataStore.newBackgroundContext
        
        try await backgroundContext.perform { [weak self] in
            guard let self else { return }
            
            let reportPredicate = NSPredicate(format: "year == %d", report.year)
            let cdReport = try self.coreDataStore.fetchOrCreate(
                entityType: CDYearInReviewReport.self,
                predicate: reportPredicate,
                in: backgroundContext
            )
            
            cdReport?.year = Int32(report.year)
            
            var cdSlidesSet = Set<CDYearInReviewSlide>()
            for slide in report.slides {
                let slidePredicate = NSPredicate(format: "id == %@", slide.id.rawValue)
                let cdSlide = try self.coreDataStore.fetchOrCreate(
                    entityType: CDYearInReviewSlide.self,
                    predicate: slidePredicate,
                    in: backgroundContext
                )
                
                cdSlide?.year = Int32(slide.year)
                cdSlide?.id = slide.id.rawValue
                cdSlide?.evaluated = slide.evaluated
                cdSlide?.display = slide.display
                cdSlide?.data = slide.data
                
                if let cdSlide {
                    cdSlidesSet.insert(cdSlide)
                }
            }
            cdReport?.slides = cdSlidesSet as NSSet
            
            try self.coreDataStore.saveIfNeeded(moc: backgroundContext)
        }
    }
    
    public func createNewYearInReviewReport(year: Int, slides: [WMFYearInReviewSlide]) async throws {
        let newReport = WMFYearInReviewReport(year: year, slides: slides)
        
        try await saveYearInReviewReport(newReport)
    }
    
    public func fetchYearInReviewReport(forYear year: Int) throws -> WMFYearInReviewReport? {
        assert(Thread.isMainThread, "This report must be called from the main thread in order to keep it synchronous")
        
        let viewContext = try coreDataStore.viewContext
        
        let fetchRequest = NSFetchRequest<CDYearInReviewReport>(entityName: "CDYearInReviewReport")
        
        fetchRequest.predicate = NSPredicate(format: "year == %d", year)
        
        let cdReports = try viewContext.fetch(fetchRequest)
        
        guard let cdReport = cdReports.first else {
            return nil
        }
        
        guard let cdSlides = cdReport.slides as? Set<CDYearInReviewSlide> else {
            return nil
        }
        
        var slides: [WMFYearInReviewSlide] = []
        for cdSlide in cdSlides {
            if let id = self.getSlideId(cdSlide.id) {
                let slide = WMFYearInReviewSlide(
                    year: Int(cdSlide.year),
                    id: id,
                    evaluated: cdSlide.evaluated,
                    display: cdSlide.display,
                    data: cdSlide.data
                )
                slides.append(slide)
            }
        }
        
        let report = WMFYearInReviewReport(
            year: Int(cdReport.year),
            slides: slides
        )
        return report
    }
    
    
    public func fetchYearInReviewReports() async throws -> [WMFYearInReviewReport] {
        let viewContext = try coreDataStore.viewContext
        let reports: [WMFYearInReviewReport] = try await viewContext.perform {
            let fetchRequest = NSFetchRequest<CDYearInReviewReport>(entityName: "CDYearInReviewReport")
            let cdReports = try viewContext.fetch(fetchRequest)
            
            var results: [WMFYearInReviewReport] = []
            for cdReport in cdReports {
                guard let cdSlides = cdReport.slides as? Set<CDYearInReviewSlide> else {
                    continue
                }
                
                var slides: [WMFYearInReviewSlide] = []
                for cdSlide in cdSlides {
                    if let id = self.getSlideId(cdSlide.id) {
                        let slide = WMFYearInReviewSlide(year: Int(cdSlide.year), id: id, evaluated: cdSlide.evaluated, display: cdSlide.display)
                        slides.append(slide)
                    }
                }
                
                let report = WMFYearInReviewReport(
                    year: Int(cdReport.year),
                    slides: slides
                )
                results.append(report)
            }
            return results
        }
        return reports
    }
    
    private func getSlideId(_ idString: String?) -> WMFYearInReviewPersonalizedSlideID? {
        switch idString {
        case "readCount":
            return .readCount
        case "editCount":
            return .editCount
        default:
            return nil
        }
        
    }
    
    public func deleteYearInReviewReport(year: Int) async throws {
        let backgroundContext = try coreDataStore.newBackgroundContext
        
        try await backgroundContext.perform { [weak self] in
            guard let self else { return }
            
            let reportPredicate = NSPredicate(format: "year == %d", year)
            if let cdReport = try self.coreDataStore.fetch(
                entityType: CDYearInReviewReport.self,
                predicate: reportPredicate,
                fetchLimit: 1,
                in: backgroundContext
            )?.first {
                backgroundContext.delete(cdReport)
                try self.coreDataStore.saveIfNeeded(moc: backgroundContext)
            }
        }
    }
    
    public func deleteAllYearInReviewReports() async throws {
        let backgroundContext = try coreDataStore.newBackgroundContext
        
        try await backgroundContext.perform {
            let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "CDYearInReviewReport")
            let batchDeleteRequest = NSBatchDeleteRequest(fetchRequest: fetchRequest)
            batchDeleteRequest.resultType = .resultTypeObjectIDs
            let result = try backgroundContext.execute(batchDeleteRequest) as? NSBatchDeleteResult
            
            if let objectIDArray = result?.result as? [NSManagedObjectID], !objectIDArray.isEmpty {
                let changes = [NSDeletedObjectsKey: objectIDArray]
                NSManagedObjectContext.mergeChanges(fromRemoteContextSave: changes, into: [backgroundContext])
            }
            try self.coreDataStore.saveIfNeeded(moc: backgroundContext)
        }
    }
    
    public func fetchUserContributionsCount(username: String, project: WMFProject?, startDate: String, endDate: String) async throws -> (Int, Bool) {
        return try await withCheckedThrowingContinuation { continuation in
            fetchUserContributionsCount(username: username, project: project, startDate: startDate, endDate: endDate) { result in
                switch result {
                case .success(let successResult):
                    continuation.resume(returning: successResult)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    public func fetchUserContributionsCount(username: String, project: WMFProject?, startDate: String, endDate: String, completion: @escaping (Result<(Int, Bool), Error>) -> Void) {
        guard let service = service else {
            completion(.failure(WMFDataControllerError.mediaWikiServiceUnavailable))
            return
        }

        guard let project = project else {
            completion(.failure(WMFDataControllerError.mediaWikiServiceUnavailable))
            return
        }
        
        // We have to switch the dates here before sending into the API.
        // It is expected that this method's startDate parameter is chronologically earlier than endDate. This is how the remote feature config is set up.
        // The User Contributions API expects ucend to be chronologically earlier than ucstart, because it pages backwards so that the most recent edits appear on the first page.
        let ucStartDate = endDate
        let ucEndDate = startDate
        
        let parameters: [String: Any] = [
            "action": "query",
            "format": "json",
            "list": "usercontribs",
            "formatversion": "2",
            "uclimit": "500",
            "ucstart": ucStartDate,
            "ucend": ucEndDate,
            "ucuser": username,
            "ucnamespace": "0",
            "ucprop": "ids|title|timestamp|tags|flags"
        ]
        
        guard let url = URL.mediaWikiAPIURL(project: project) else {
            completion(.failure(WMFDataControllerError.failureCreatingRequestURL))
            return
        }
        
        let request = WMFMediaWikiServiceRequest(url: url, method: .GET, backend: .mediaWiki, parameters: parameters)
        
        service.performDecodableGET(request: request) { (result: Result<UserContributionsAPIResponse, Error>) in
            switch result {
            case .success(let response):
                guard let query = response.query else {
                    completion(.failure(WMFDataControllerError.unexpectedResponse))
                    return
                }
                
                let editCount = query.usercontribs.count
                
                let hasMoreEdits = response.continue?.uccontinue != nil
                
                completion(.success((editCount, hasMoreEdits)))
                
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    struct UserContributionsAPIResponse: Codable {
        let batchcomplete: Bool?
        let `continue`: ContinueData?
        let query: UserContributionsQuery?
        
        struct ContinueData: Codable {
            let uccontinue: String?
        }
        
        struct UserContributionsQuery: Codable {
            let usercontribs: [UserContribution]
        }
    }
    
    struct UserContribution: Codable {
        let userid: Int
        let user: String
        let pageid: Int
        let revid: Int
        let parentid: Int
        let ns: Int
        let title: String
        let timestamp: String
        let isNew: Bool
        let isMinor: Bool
        let isTop: Bool
        let tags: [String]
        
        enum CodingKeys: String, CodingKey {
            case userid, user, pageid, revid, parentid, ns, title, timestamp, tags
            case isNew = "new"
            case isMinor = "minor"
            case isTop = "top"
        }
    }
}