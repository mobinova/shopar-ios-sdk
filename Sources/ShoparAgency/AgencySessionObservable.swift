import Combine

@MainActor
public final class AgencySessionObservable:ObservableObject{
    @Published public private(set) var session:AgencyCreatorSession?
    public init(){}
    func update(_ value:AgencyCreatorSession?){session=value}
}
