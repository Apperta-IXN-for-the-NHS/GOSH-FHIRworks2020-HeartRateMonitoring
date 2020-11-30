//
//  InterfaceController.swift
//  HeartRateMotinoring WatchKit Extension
//
//  Created by Jan Kolarik on 02/03/2020.
//

import WatchKit
import Foundation
import HealthKit

class InterfaceController: WKInterfaceController, HKWorkoutSessionDelegate, HKLiveWorkoutBuilderDelegate {
    
    let healthStore = HKHealthStore()
    var session: HKWorkoutSession!
    var builder: HKLiveWorkoutBuilder!
    var configuration: HKWorkoutConfiguration!
    var avgHeartRate = -1.0
    var sessionRunning = 0
    var accessToken : String = ""
    
    final var FHIR_URL : String = "https://gosh-fhir-synth.azurehealthcareapis.com/"
    final var DATA_TYPE : String = "heartrate"
    final var PATIENT_ID : String = "8f789d0b-3145-4cf2-8504-13159edaa747"
    final var UNIT : String = "BPM"
    final var RESOURCE_TYPE : String = "Observation"
    final var STATUS : String = "final"
    final var CODE : String = "8867-4"
    final var SYSTEM : String = "http://loinc.org"
    final var DISPLAY : String = "Heart rate"
    final var SESSION_NOT_RUNNING : Int = 0
    final var SESSION_RUNNING : Int = 1
    final var DEFAULT_VALUE : Double = -1.0

    @IBOutlet weak var heartRateLabel: WKInterfaceLabel!
    @IBOutlet weak var timer: WKInterfaceTimer!
    @IBOutlet weak var dateAndTime: WKInterfaceDate!
    @IBOutlet weak var activityButton: WKInterfaceButton!
    
    override func awake(withContext context: Any?) {
        super.awake(withContext: context)
        permissions()
        configure()
    }
    
    //Logic for the following code used and modified from main project "Dance Health"
    @IBAction func buttonPressed() {
        if(sessionRunning == SESSION_NOT_RUNNING){
            startSession()
            sessionRunning = SESSION_RUNNING
            activityButton.setTitle("Stop Measuring")
            getToken()
        }
        else{
            endSession()
            sessionRunning = SESSION_NOT_RUNNING
            activityButton.setTitle("Start Measuring")
            sendData()
        }
        
    }
    
    override func willActivate() {
        // This method is called when watch view controller is about to be visible to user
        super.willActivate()
    }
    
    override func didDeactivate() {
        // This method is called when watch view controller is no longer visible
        super.didDeactivate()
    }
    
    //https://developer.apple.com/documentation/healthkit/workouts_and_activity_rings/running_workout_sessions
    func configure(){
        configuration = HKWorkoutConfiguration()
        configuration.activityType = .other
        configuration.locationType = .unknown
    }
    
    func startSession(){
        do {
            session = try HKWorkoutSession(healthStore: healthStore, configuration: configuration)
            builder = session.associatedWorkoutBuilder()
        } catch {
            return
        }
        builder.dataSource = HKLiveWorkoutDataSource(healthStore: healthStore,
        workoutConfiguration: configuration)
        
        session.startActivity(with: Date())
        builder.beginCollection(withStart: Date()) { (success, error) in
            self.setDurationTimerDate(.running)
        }
        session.delegate = self
        builder.delegate = self
    }
    
    func endSession(){
        builder.endCollection(withEnd: Date()) { (success, error) in
            self.builder.finishWorkout { (workout, error) in
                // Dispatch to main, because we are updating the interface.
                DispatchQueue.main.async() {
                    self.dismiss()
                }
            }
        }
        session.end()
        self.setDurationTimerDate(.ended)
    }
    
    func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {
        let lastEvent = workoutBuilder.workoutEvents.last
    }
    
    func permissions(){
        // The quantity type to write to the health store.
        let typesToShare: Set = [
            HKQuantityType.workoutType()
        ]

        // The quantity types to read from the health store.
        let typesToRead: Set = [
            HKQuantityType.quantityType(forIdentifier: .heartRate)!
        ]

        // Request authorization for those quantity types.
        healthStore.requestAuthorization(toShare: typesToShare, read: typesToRead) { (success, error) in
        }
    }
    
    // MARK: - Delegates
    
    //Used from SpeedySloth example code from Apple, with permission
     func setDurationTimerDate(_ sessionState: HKWorkoutSessionState) {
         /// Obtain the elapsed time from the workout builder.
         /// - Tag: ObtainElapsedTime
         let timerDate = Date(timeInterval: -self.builder.elapsedTime, since: Date())
         
         // Dispatch to main, because we are updating the interface.
         DispatchQueue.main.async {
             self.timer.setDate(timerDate)
         }
         
         // Dispatch to main, because we are updating the interface.
         DispatchQueue.main.async {
             /// Update the timer based on the state we are in.
             /// - Tag: UpdateTimer
             sessionState == .running ? self.timer.start() : self.timer.stop()
         }
     }
    
    // MARK: - HKWorkoutSessionDelegate
    func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didChangeTo toState: HKWorkoutSessionState,
        from fromState: HKWorkoutSessionState,
        date: Date
    ) {}
    
    func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
    }
    
    // MARK: - HKLiveWorkoutBuilderDelegate
    //Used and modified from main project "Dance Health"
    func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        if let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate), let statistics = workoutBuilder.statistics(for: heartRateType){
            let heartRateUnit = HKUnit.count().unitDivided(by: HKUnit.minute())
            let value = statistics.mostRecentQuantity()?.doubleValue(for: heartRateUnit)
            let roundedValue = Double( round( 1 * value! ) / 1 )
            heartRateLabel.setText("\(roundedValue) BPM")
            avgHeartRate = roundedValue
        }
    }
    
    // MARK: - FHIR API
    
    //With help from Usman Bahadur, modified
    func getToken(){
        let CLIENT_ID = "0f6332f4-c060-49fc-bcf6-548982d56569"
        let CLIENT_SECRET = "ux@CJAaxCD85A9psm-Wdb?x3/Z4c6gp9"
        let SCOPE = "https://gosh-fhir-synth.azurehealthcareapis.com/.default"
        let payload = "grant_type=client_credentials&client_id=\(CLIENT_ID)&client_secret=\(CLIENT_SECRET)&scope=\(SCOPE)"
        let url = "https://login.microsoftonline.com/ca254449-06ec-4e1d-a3c9-f8b84e2afe3f/oauth2/v2.0/token"

        let session = URLSession.shared
        let postURL = URL(string: url)!
        var request = URLRequest(url: postURL)
        request.httpMethod = "POST"
        request.addValue("application/x-www-form-urlencoded", forHTTPHeaderField: "content-type")
        request.httpBody = payload.data(using: String.Encoding.utf8)!
        
        //https://stackoverflow.com/questions/26364914/http-request-in-swift-with-post-method, Date accessed 18/03/2020
        let task = session.dataTask(with: request as URLRequest, completionHandler: { data, response, error in

            guard error == nil else {
                return
            }

            guard let data = data else {
                return
            }
            do {
                if let json = try JSONSerialization.jsonObject(with: data, options: .mutableContainers) as? [String: Any] {
                    self.accessToken = json["access_token"] as! String
                }
            } catch let error {
                print(error.localizedDescription)
            }
        })
        task.resume()
    }
    
    // MARK: - Sending Data
    func getDate() -> String{
        let today = Date()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSS'z'"
        return formatter.string(from: today)
    }
    
    func createJSON() -> [String : Any]{
        return [
            "resourceType": RESOURCE_TYPE,
            "status": STATUS,
            "code": [
                "text": DATA_TYPE,
                "coding": [
                    [
                        "code": CODE,
                        "system": SYSTEM,
                        "display": DISPLAY
                    ]
                ]
            ],
            "subject": [
                "reference": "Patient/8f789d0b-3145-4cf2-8504-13159edaa747"
            ],
            "effectivePeriod": [
                "start": getDate(),
                "end": getDate()
            ],
            "component": [],
            "valueQuantity": [
                "value": avgHeartRate,
                "unit": UNIT
            ]
        ]
    }

    func sendData(){
        if(avgHeartRate == DEFAULT_VALUE){
            return
        }
        
        let observationJSONSerialized = try? JSONSerialization.data(withJSONObject: createJSON())
        
        let session = URLSession.shared
        let url = URL(string: "https://gosh-fhir-synth.azurehealthcareapis.com/Observation")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = observationJSONSerialized
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        let task = session.dataTask(with: request as URLRequest, completionHandler: { data, response, error in
            print("Heart Rate recorded = \(self.avgHeartRate)")
            print(response)
        })
        task.resume()
    }
 
}
