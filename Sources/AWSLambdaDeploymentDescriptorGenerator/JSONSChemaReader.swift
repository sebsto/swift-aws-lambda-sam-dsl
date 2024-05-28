/*
 This struct represent a subset of a JSONSchema
 We focus implementation to specifically decode the SAM Template JSON Schema,
 as defined at https://github.com/aws/serverless-application-model/blob/develop/samtranslator/validator/sam_schema/schema.json
 
 We do not intent to create a generic JSON SChema decoder.
 */
struct JSONSchema: Decodable, Sendable {
    let id: String?
    let schema: JSONSchemaDialectVersion
    let description: String?
    let type: JSONPrimitiveType
    let properties: [String: JSONUnionType]?
    let additionalProperties: Bool?
    let required : [String]?
    let definitions: [String: JSONUnionType]?

    enum CodingKeys: String, CodingKey {
        case id = "$id"
        case schema = "$schema"
        case definitions = "$defs"
        case description
        case type
        case properties
        case additionalProperties
        case required
    }
    enum CodingKeys_draft4: String, CodingKey {
        case definitions = "definitions"
    }

    // implement a custom init(from:) method to support different schema version
    init(from decoder: any Decoder) throws {
        
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        self.id = try container.decodeIfPresent(String.self, forKey: .id)
        self.schema = try container.decode(JSONSchemaDialectVersion.self, forKey: .schema)
        self.description = try container.decodeIfPresent(String.self, forKey: .description)
        self.type = try container.decode(JSONPrimitiveType.self, forKey: .type)
        self.properties = try container.decodeIfPresent([String: JSONUnionType].self, forKey: .properties)
        self.additionalProperties = try container.decodeIfPresent(Bool.self, forKey: .additionalProperties)
        self.required = try container.decodeIfPresent([String].self, forKey: .required)
        
        // support multiple version of the "definition" key, depending on JSON Schema version
        // introduced by version 2019-09
        // https://json-schema.org/draft/2019-09/release-notes#semi-incompatible-changes
       switch self.schema {
       case .v2019_09, .v2020_12:
             self.definitions = try container.decodeIfPresent([String: JSONUnionType].self, forKey: .definitions)
       case .draft4:
             let container = try decoder.container(keyedBy: CodingKeys_draft4.self)
             self.definitions = try container.decodeIfPresent([String: JSONUnionType].self, forKey: .definitions)
       }
    }

}

// This represents the multiple versions of a JSON Schema
// https://json-schema.org/specification-links
enum JSONSchemaDialectVersion: String, Equatable, Decodable, Sendable {
    
    // the versions we support
    case draft4 = "http://json-schema.org/draft-04/schema#"
    case v2019_09 = "https://json-schema.org/draft/2019-09/schema"
    case v2020_12 = "https://json-schema.org/draft/2020-12/schema"
    
    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let schemaString = try container.decode(String.self)
        
        if schemaString.contains("2020-12") {
            self = .v2020_12
        } else if schemaString.contains("2019-09") {
            self = .v2019_09
        } else if schemaString.contains("draft-04") {
            self = .draft4
        } else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context.init(
                    codingPath: container.codingPath,
                    debugDescription: "Unspported schema version: \(schemaString)"))
        }
    }
}

// A JSON primitive type
// https://json-schema.org/understanding-json-schema/reference/type
enum JSONPrimitiveType: Decodable, Equatable, Sendable {
    case string
    case object
    case boolean
    case array
    case integer
    case number
    case null
    
    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        if value == "string" {
            self = .string
        } else if value == "object" {
            self = .object
        } else if value == "boolean" {
            self = .boolean
        } else if value == "object" {
            self = .object
        } else if value == "array" {
            self = .array
        } else if value == "integer" {
            self = .integer
        } else if value == "number" {
            self = .number
        } else {
            throw DecodingError.typeMismatch(JSONPrimitiveType.self, DecodingError.Context.init(codingPath: container.codingPath, debugDescription: "Unknown value (\(value)) for type property. Please make sure the schema refers to https://json-schema.org/understanding-json-schema/reference/type", underlyingError: nil))
        }
    }
}

// a JSON Union Type
enum JSONUnionType: Decodable, Sendable {
    case anyOf([JSONType])
    case allOf([JSONUnionType])
    case type(JSONType)
    
    enum CodingKeys: String, CodingKey {
        case anyOf
        case allOf
    }
    
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        var allKeys = ArraySlice(container.allKeys)
        if let onlyKey = allKeys.popFirst(), allKeys.isEmpty  {
            // there is an anyOf or allOf key
            switch onlyKey {
            case .allOf:
                let value = try container.decode(Array<JSONUnionType>.self, forKey: .allOf)
                self = .allOf(value)
            case .anyOf:
                let value = try container.decode(Array<JSONType>.self, forKey: .anyOf)
                self = .anyOf(value)
            }
        } else {
            // there is no anyOf or allOf key, the entry is a JSONType
            let container = try decoder.singleValueContainer()
            let value = try container.decode(JSONType.self)
            self = .type(value)
        }
    }
    
    // convenience function to extract a JSONType from this enum
    func jsonType() -> JSONType {
        guard case .type(let jsonType) = self else {
            fatalError("not a JSONType")
        }
        
        return jsonType
    }
    
    func any() -> [JSONType]? {
        guard case .anyOf(let anyOf) = self else {
            fatalError("not an anyOf")
        }
        
        return anyOf
    }
    
    func all() -> [JSONUnionType]? {
        guard case .allOf(let allOf) = self else {
            fatalError("not an allOf")
        }
        
        return allOf
    }
}

// a JSON type
struct JSONType: Decodable, Sendable {

    let type: [JSONPrimitiveType]?
    let reference: String?
    let required: [String]?
    let description: String?
    let additionalProperties: Bool?
    let enumeration: [String]?
    
    let subType: SubTypeSchema?

    // Nested enums for specific schema types
    indirect enum SubTypeSchema {
        case string(StringSchema)
        case object(ObjectSchema)
        case array(ArraySchema)
        case number(NumberSchema)
        case boolean
        case null
    }
    
    // for Object
    // https://json-schema.org/understanding-json-schema/reference/object
    struct ObjectSchema: Decodable, Sendable {
        enum CodingKeys: String, CodingKey {
            case properties
            case patternProperties
            case minProperties
            case maxProperties
        }
        
        let properties: [String: JSONUnionType]?
        let patternProperties: [String: JSONUnionType]?
        let minProperties: Int?
        let maxProperties: Int?

        // Validate required within string array if present
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.properties = try container.decodeIfPresent([String: JSONUnionType].self, forKey: .properties)
            self.patternProperties = try container.decodeIfPresent([String: JSONUnionType].self, forKey: .patternProperties)
            self.minProperties = try container.decodeIfPresent(Int.self, forKey: .minProperties)
            self.maxProperties = try container.decodeIfPresent(Int.self, forKey: .maxProperties)
        }
    }
    
    // for String
    // https://json-schema.org/understanding-json-schema/reference/string
    struct StringSchema: Decodable, Sendable {
        let pattern: String?
        let minLength: Int?
        let maxLength: Int?
        
        // not used in SAM Schema
//        let format: String  
        
        enum CodingKeys: String, CodingKey {
            case pattern
            case minLength
            case maxLength
        }
        
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.pattern = try container.decodeIfPresent(String.self, forKey: .pattern)
            self.minLength = try container.decodeIfPresent(Int.self, forKey: .minLength)
            self.maxLength = try container.decodeIfPresent(Int.self, forKey: .maxLength)
        }
    }
    
    // for Array type
    // https://json-schema.org/understanding-json-schema/reference/array
    struct ArraySchema: Decodable, Sendable {
        let items: JSONType?
        let minItems: Int?
        
        enum CodingKeys: String, CodingKey {
            case items
            case minItems
        }
        
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            items = try container.decodeIfPresent(JSONType.self, forKey: .items)
            minItems = try container.decodeIfPresent(Int.self, forKey: .minItems)
        }
        
        // let prefixItems
        // let unevaluatedItems
        // let contains
        // let minContains
        // let maxContains
        // let maxItems
        // let uniqueItems
    }
    
    // for Number
    // https://json-schema.org/understanding-json-schema/reference/numeric
    struct NumberSchema: Decodable, Sendable {
        let multipleOf: Double?
        let minimum: Double?
        let exclusiveMinimum: Bool?
        let maximum: Double?
        let exclusiveMaximum: Bool?
        
        enum CodingKeys: String, CodingKey {
            case multipleOf
            case minimum
            case exclusiveMinimum
            case maximum
            case exclusiveMaximum
        }
        
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            
            multipleOf = try container.decodeIfPresent(Double.self, forKey: .multipleOf)
            minimum = try container.decodeIfPresent(Double.self, forKey: .minimum)
            exclusiveMinimum = try container.decodeIfPresent(Bool.self, forKey: .exclusiveMinimum)
            maximum = try container.decodeIfPresent(Double.self, forKey: .maximum)
            exclusiveMaximum = try container.decodeIfPresent(Bool.self, forKey: .exclusiveMaximum)
            
        }
    }
    
    enum CodingKeys: String, CodingKey {
        case type
        case reference = "$ref"
        case enumeration = "enum"
        case required
        case description
        case additionalProperties
    }
    
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        // check if this is a single value or an array
        if let primitiveType = try? container.decodeIfPresent(JSONPrimitiveType.self, forKey: .type) {
            // and store it as an array of one element
            self.type = [primitiveType]
        } else {
            // if it doesn't work, try to decode an array
            let arrayOfPrimitiveType = try? container.decodeIfPresent([JSONPrimitiveType].self, forKey: .type)
            
            // if it doesn't work, type is nil
            self.type = arrayOfPrimitiveType
        }
        
        // if there is only one type, check the subtype
        if let type = self.type, type.count == 1 {
            switch type[0] {
            case .string:
                self.subType = .string(try StringSchema(from: decoder))
            case .object:
                self.subType = .object(try ObjectSchema(from: decoder))
            case .array:
                self.subType = .array(try ArraySchema(from: decoder))
            case .number:
                self.subType = .number(try NumberSchema(from: decoder))
            case .boolean:
                self.subType = .boolean
            case .integer:
                self.subType = .number(try NumberSchema(from: decoder))
            case .null:
                self.subType = .null
            }
        } else {
            self.subType = nil
        }
        
        self.enumeration = try container.decodeIfPresent([String].self, forKey: .enumeration)
        self.required = try container.decodeIfPresent([String].self, forKey: .required)
        self.description = try container.decodeIfPresent(String.self, forKey: .description)
        self.additionalProperties = try container.decodeIfPresent(Bool.self, forKey: .additionalProperties)
        self.reference = try container.decodeIfPresent(String.self, forKey: .reference)
    }
    
    // MARK: accessor methods to easily access associated value of TypeSchema
    // question, instead of return nil, should we raise a fatalerror() ?
    // TODO: we should have one method for each TypeSchema


    func object() -> ObjectSchema? {
        if case let .object(schema) = self.subType {
            return schema
        }
        return nil
    }

    func object(for property:String) -> JSONUnionType? {
        if case let .object(schema) = self.subType {
            return schema.properties?[property]
        }
        return nil
    }

    func stringSchema() -> StringSchema? {
        if case let .string(schema) = self.subType {
            return schema
        }
        return nil
    }
    
    func arraySchema() -> ArraySchema? {
        if case let .array(schema) = self.subType {
            return schema
        }
        return nil
    }

    func items() -> JSONType? {
        if case let .array(schema) = self.subType {
            return schema.items
        }
        return nil
    }
}
