import Foundation

/// The public Top 20 services of one learner: its own alias, participation,
/// pending best and participant ID, as Android keeps a LeaderboardProfile per
/// child slot (LeaderboardState). Unlike the other per-child values, they are
/// named by the learner's owner ID rather than exchanged, because a record
/// submission may still be running when another child is chosen; it then
/// finishes with the identity of the child it started for. One anonymous
/// Firebase user owns all the children's participant IDs.
enum ChildProfileRecordsComposition {
    struct Services {
        let submission: RewardRecordSubmissionService
        let isConfigured: Bool
    }

    @MainActor
    static func make(
        product: ProductVariant,
        ownerID: RewardOwnerID,
        injectedRepository: (any RecordsRepository)? = nil
    ) -> Services {
        let scope = RewardScope(ownerID: ownerID, product: product)
        let stateStore = UserDefaultsPublicLeaderboardStateStore(scope: scope)
        let repository = injectedRepository ?? ProductionRecordsRepositoryFactory.make(
            for: product,
            ownerID: ownerID,
            publicLeaderboardStore: stateStore
        )
        return Services(
            submission: RewardRecordSubmissionService(
                scope: scope,
                repository: repository,
                localStateStore: stateStore
            ),
            isConfigured: repository != nil
        )
    }
}
