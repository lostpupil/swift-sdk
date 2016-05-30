//
//  Query.swift
//  LeanCloud
//
//  Created by Tang Tianyong on 4/19/16.
//  Copyright © 2016 LeanCloud. All rights reserved.
//

import Foundation

/**
 Query defines a query for objects.
 */
final public class Query {
    /// Query class name.
    public private(set) var className: String

    /// The limit on the number of objects to return.
    public var limit: Int?

    /// The number of objects to skip before returning.
    public var skip: Int?

    /// Included keys.
    private var includedKeys: Set<String> = []

    /// Selected keys.
    private var selectedKeys: Set<String> = []

    /// Equality table.
    private var equalityTable: [String: LCType] = [:]

    /// Equality key-value pairs.
    private var equalityPairs: [[String: LCType]] {
        return equalityTable.map { [$0: $1] }
    }

    /// Ordered keys.
    private var orderedKeys: String?

    /// Dictionary of constraints indexed by key.
    /// Note that it may contains LCType or Query value.
    private var constraintDictionary: [String: AnyObject] = [:]

    /// JSON representation of query.
    var JSONValue: [String: AnyObject] {
        var dictionary: [String: AnyObject] = [:]

        dictionary["className"] = className

        if !constraintDictionary.isEmpty {
            dictionary["where"] = ObjectProfiler.JSONValue(constraintDictionary)
        }
        if !includedKeys.isEmpty {
            dictionary["include"] = includedKeys.joinWithSeparator(",")
        }
        if !selectedKeys.isEmpty {
            dictionary["keys"] = selectedKeys.joinWithSeparator(",")
        }
        if let orderedKeys = orderedKeys {
            dictionary["order"] = orderedKeys
        }
        if let limit = limit {
            dictionary["limit"] = limit
        }
        if let skip = skip {
            dictionary["skip"] = skip
        }

        return dictionary
    }

    /// Parameters for query request.
    private var parameters: [String: AnyObject] {
        var parameter = JSONValue

        /* Encode where field to string. */
        if let object = parameter["where"] {
            parameter["where"] = Utility.JSONString(object)
        }

        return parameter
    }

    /// The dispatch queue for network request task.
    static let backgroundQueue = dispatch_queue_create("LeanCloud.Query", DISPATCH_QUEUE_CONCURRENT)

    /**
     Constraint for key.
     */
    public enum Constraint {
        case Included
        case Selected
        case Existed
        case NotExisted

        case EqualTo(value: LCType)
        case NotEqualTo(value: LCType)
        case LessThan(value: LCType)
        case LessThanOrEqualTo(value: LCType)
        case GreaterThan(value: LCType)
        case GreaterThanOrEqualTo(value: LCType)

        case ContainedIn(array: LCArray)
        case NotContainedIn(array: LCArray)
        case ContainedAllIn(array: LCArray)
        case EqualToSize(size: LCNumber)

        case NearbyPoint(point: LCGeoPoint)
        case NearbyPointWithRange(point: LCGeoPoint, from: LCGeoPoint.Distance?, to: LCGeoPoint.Distance?)
        case NearbyPointWithRectangle(southwest: LCGeoPoint, northeast: LCGeoPoint)

        case MatchedQuery(query: Query)
        case NotMatchedQuery(query: Query)
        case MatchedQueryAndKey(query: Query, key: String)
        case NotMatchedQueryAndKey(query: Query, key: String)

        case MatchedPattern(pattern: String, option: String?)
        case MatchedSubstring(string: String)
        case PrefixedBy(string: String)
        case SuffixedBy(string: String)

        case RelatedTo(object: LCObject)

        case Ascending
        case Descending
    }

    var endpoint: String {
        return RESTClient.endpoint(className)
    }

    /**
     Construct query with class name.

     - parameter className: The class name to query.
     */
    public init(className: String) {
        self.className = className
    }

    /**
     Add constraint in query.

     - parameter constraint: The constraint.
     */
    public func whereKey(key: String, _ constraint: Constraint) {
        var dictionary: [String: AnyObject]?

        switch constraint {
        /* Key matching. */
        case .Included:
            includedKeys.insert(key)
        case .Selected:
            selectedKeys.insert(key)
        case .Existed:
            dictionary = ["$exists": true]
        case .NotExisted:
            dictionary = ["$exists": false]

        /* Equality matching. */
        case let .EqualTo(value):
            equalityTable[key] = value
            constraintDictionary["$and"] = equalityPairs
        case let .NotEqualTo(value):
            dictionary = ["$ne": value]
        case let .LessThan(value):
            dictionary = ["$lt": value]
        case let .LessThanOrEqualTo(value):
            dictionary = ["$lte": value]
        case let .GreaterThan(value):
            dictionary = ["$gt": value]
        case let .GreaterThanOrEqualTo(value):
            dictionary = ["$gte": value]

        /* Array matching. */
        case let .ContainedIn(array):
            dictionary = ["$in": array]
        case let .NotContainedIn(array):
            dictionary = ["$nin": array]
        case let .ContainedAllIn(array):
            dictionary = ["$all": array]
        case let .EqualToSize(size):
            dictionary = ["$size": size]

        /* Geography point matching. */
        case let .NearbyPoint(point):
            dictionary = ["$nearSphere": point]
        case let .NearbyPointWithRange(point, min, max):
            var value: [String: AnyObject] = ["$nearSphere": point]
            if let min = min { value["$minDistanceIn\(min.unit.rawValue)"] = min.value }
            if let max = max { value["$maxDistanceIn\(max.unit.rawValue)"] = max.value }
            dictionary = value
        case let .NearbyPointWithRectangle(southwest, northeast):
            dictionary = ["$within": ["$box": [southwest, northeast]]]

        /* Query matching. */
        case let .MatchedQuery(query):
            dictionary = ["$inQuery": query]
        case let .NotMatchedQuery(query):
            dictionary = ["$notInQuery": query]
        case let .MatchedQueryAndKey(query, key):
            dictionary = ["$select": ["query": query, "key": key]]
        case let .NotMatchedQueryAndKey(query, key):
            dictionary = ["$dontSelect": ["query": query, "key": key]]

        /* String matching. */
        case let .MatchedPattern(pattern, option):
            dictionary = ["$regex": pattern, "$options": option ?? ""]
        case let .MatchedSubstring(string):
            dictionary = ["$regex": "\(string.regularEscapedString)"]
        case let .PrefixedBy(string):
            dictionary = ["$regex": "^\(string.regularEscapedString)"]
        case let .SuffixedBy(string):
            dictionary = ["$regex": "\(string.regularEscapedString)$"]

        case let .RelatedTo(object):
            constraintDictionary["$relatedTo"] = ["object": object, "key": key]

        case .Ascending:
            appendOrderedKey(key)
        case .Descending:
            appendOrderedKey("-\(key)")
        }

        if let dictionary = dictionary {
            addConstraint(key, dictionary)
        }
    }

    /**
     Validate query class name.

     - parameter query: The query to be validated.
     */
    func validateClassName(query: Query) {
        guard query.className == className else {
            Exception.raise(.Inconsistency, reason: "Different class names.")
            return
        }
    }

    /**
     Get logic AND of another query.

     Note that it only combine constraints of two queries, the limit and skip option will be discarded.

     - parameter query: The another query.

     - returns: The logic AND of two queries.
     */
    func logicAnd(query: Query) -> Query {
        validateClassName(query)

        let result = Query(className: className)

        result.constraintDictionary["$and"] = [self.constraintDictionary, query.constraintDictionary]

        return result
    }

    /**
     Get logic OR of another query.

     Note that it only combine constraints of two queries, the limit and skip option will be discarded.

     - parameter query: The another query.

     - returns: The logic OR of two queries.
     */
    func logicOr(query: Query) -> Query {
        validateClassName(query)

        let result = Query(className: className)

        result.constraintDictionary["$or"] = [self.constraintDictionary, query.constraintDictionary]

        return result
    }

    /**
     Append ordered key to ordered keys string.

     - parameter orderedKey: The ordered key with optional '-' prefixed.
     */
    func appendOrderedKey(orderedKey: String) {
        orderedKeys = orderedKeys?.stringByAppendingString(orderedKey) ?? orderedKey
    }

    /**
     Add a constraint for key.

     - parameter key:        The key on which the constraint to be added.
     - parameter dictionary: The constraint dictionary for key.
     */
    func addConstraint(key: String, _ dictionary: [String: AnyObject]) {
        constraintDictionary[key] = dictionary
    }

    /**
     Transform JSON results to objects.

     - parameter results: The results return by query.

     - returns: An array of LCObject objects.
     */
    func processResults<T: LCObject>(results: [AnyObject], className: String?) -> [T] {
        return results.map { dictionary in
            let object = ObjectProfiler.object(className: className ?? self.className) as! T

            if let dictionary = dictionary as? [String: AnyObject] {
                ObjectProfiler.updateObject(object, dictionary)
            }

            return object
        }
    }

    /**
     Asynchronize task into background queue.

     - parameter task:       The task to be performed.
     - parameter completion: The completion closure to be called on main thread after task finished.
     */
    static func asynchronize<Result>(task: () -> Result, completion: (Result) -> Void) {
        Utility.asynchronize(task, backgroundQueue, completion)
    }

    /**
     Query objects synchronously.

     - returns: The result of the query request.
     */
    public func find<T: LCObject>() -> QueryResult<T> {
        let response = RESTClient.request(.GET, endpoint, parameters: parameters)

        if let error = response.error {
            return .Failure(error: error)
        } else {
            let className = response.value?["className"] as? String
            let objects: [T] = processResults(response.results, className: className)

            return .Success(objects: objects)
        }
    }

    /**
     Query objects asynchronously.

     - parameter completion: The completion callback closure.
     */
    public func find<T: LCObject>(completion: (QueryResult<T>) -> Void) {
        Query.asynchronize({ self.find() }) { result in
            completion(result)
        }
    }

    /**
     Count objects synchronously.

     - returns: The result of the count request.
     */
    public func count() -> CountResult {
        var parameters = self.parameters

        parameters["count"] = 1
        parameters["limit"] = 0

        let response = RESTClient.request(.GET, endpoint, parameters: parameters)
        let result = CountResult(response: response)

        return result
    }
}

/**
 Perform logic AND of two queries.

 - parameter left:  The left operand.
 - parameter right: Tne right operand.

 - returns: The logic AND of two queries.
 */
func && (left: Query, right: Query) -> Query {
    return left.logicAnd(right)
}

/**
 Perform logic OR of two queries.

 - parameter left:  The left operand.
 - parameter right: Tne right operand.

 - returns: The logic OR of two queries.
 */
func || (left: Query, right: Query) -> Query {
    return left.logicOr(right)
}