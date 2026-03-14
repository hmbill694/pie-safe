import gleam/dynamic/decode
import gleam/option

pub type Role {
  Admin
  RegularMember
}

pub type Member {
  Member(
    id: Int,
    email: String,
    first_name: String,
    last_name: String,
    date_of_birth: String,
    role: Role,
    is_managed: Bool,
  )
}

pub type Allergy {
  Allergy(id: Int, name: String, severity: String, notes: String)
}

pub type Medication {
  Medication(
    id: Int,
    name: String,
    dosage: String,
    frequency: String,
    prescribing_provider: String,
  )
}

pub type Immunization {
  Immunization(
    id: Int,
    vaccine_name: String,
    date_administered: String,
    administered_by: String,
  )
}

pub type InsurancePolicy {
  InsurancePolicy(
    id: Int,
    provider_name: String,
    policy_number: String,
    group_number: String,
    plan_type: String,
  )
}

pub type Provider {
  Provider(
    id: Int,
    name: String,
    specialty: String,
    phone: String,
    address: String,
  )
}

pub type EmergencyContact {
  EmergencyContact(id: Int, name: String, relationship: String, phone: String)
}

pub type Document {
  Document(id: Int, name: String, document_type: String, notes: String)
}

pub type MemberWithData {
  MemberWithData(
    member: Member,
    allergies: List(Allergy),
    medications: List(Medication),
    immunizations: List(Immunization),
    insurance_policies: List(InsurancePolicy),
    providers: List(Provider),
    emergency_contacts: List(EmergencyContact),
    documents: List(Document),
  )
}

pub fn member_decoder() -> decode.Decoder(Member) {
  use id <- decode.field("id", decode.int)
  use email <- decode.field("email", decode.optional(decode.string))
  use first_name <- decode.field("first_name", decode.string)
  use last_name <- decode.field("last_name", decode.string)
  use date_of_birth <- decode.field(
    "date_of_birth",
    decode.optional(decode.string),
  )
  use role_str <- decode.field("role", decode.string)
  use is_managed_int <- decode.field("is_managed", decode.int)
  let role = case role_str {
    "admin" -> Admin
    _ -> RegularMember
  }
  decode.success(Member(
    id:,
    email: option.unwrap(email, ""),
    first_name:,
    last_name:,
    date_of_birth: option.unwrap(date_of_birth, ""),
    role:,
    is_managed: is_managed_int != 0,
  ))
}
