import gleam/list
import gleam/option.{type Option}

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

pub fn all_members() -> List(MemberWithData) {
  [
    MemberWithData(
      member: Member(
        id: 1,
        email: "alex.johnson@example.com",
        first_name: "Alex",
        last_name: "Johnson",
        date_of_birth: "1985-03-12",
        role: Admin,
        is_managed: False,
      ),
      allergies: [
        Allergy(
          id: 1,
          name: "Peanuts",
          severity: "Severe",
          notes: "Carries EpiPen",
        ),
        Allergy(
          id: 2,
          name: "Penicillin",
          severity: "Moderate",
          notes: "Rash and hives",
        ),
      ],
      medications: [],
      immunizations: [
        Immunization(
          id: 1,
          vaccine_name: "COVID-19 (Moderna)",
          date_administered: "2023-10-15",
          administered_by: "CVS Pharmacy",
        ),
      ],
      insurance_policies: [],
      providers: [
        Provider(
          id: 1,
          name: "Dr. Sarah Chen",
          specialty: "Primary Care",
          phone: "555-234-5678",
          address: "123 Health Blvd, Springfield, IL 62701",
        ),
      ],
      emergency_contacts: [
        EmergencyContact(
          id: 1,
          name: "Morgan Johnson",
          relationship: "Spouse",
          phone: "555-876-5432",
        ),
      ],
      documents: [],
    ),
    MemberWithData(
      member: Member(
        id: 2,
        email: "morgan.johnson@example.com",
        first_name: "Morgan",
        last_name: "Johnson",
        date_of_birth: "1987-07-24",
        role: RegularMember,
        is_managed: False,
      ),
      allergies: [],
      medications: [
        Medication(
          id: 1,
          name: "Lisinopril",
          dosage: "10mg",
          frequency: "Once daily",
          prescribing_provider: "Dr. Sarah Chen",
        ),
        Medication(
          id: 2,
          name: "Metformin",
          dosage: "500mg",
          frequency: "Twice daily",
          prescribing_provider: "Dr. James Patel",
        ),
      ],
      immunizations: [],
      insurance_policies: [
        InsurancePolicy(
          id: 1,
          provider_name: "Blue Cross Blue Shield",
          policy_number: "BCB-123456789",
          group_number: "GRP-55501",
          plan_type: "PPO",
        ),
      ],
      providers: [],
      emergency_contacts: [
        EmergencyContact(
          id: 1,
          name: "Alex Johnson",
          relationship: "Spouse",
          phone: "555-345-6789",
        ),
      ],
      documents: [],
    ),
    MemberWithData(
      member: Member(
        id: 3,
        email: "",
        first_name: "Jamie",
        last_name: "Johnson",
        date_of_birth: "2016-05-18",
        role: RegularMember,
        is_managed: True,
      ),
      allergies: [
        Allergy(
          id: 1,
          name: "Dairy",
          severity: "Mild",
          notes: "Lactose intolerant",
        ),
      ],
      medications: [],
      immunizations: [
        Immunization(
          id: 1,
          vaccine_name: "MMR",
          date_administered: "2017-05-20",
          administered_by: "Pediatric Associates",
        ),
      ],
      insurance_policies: [],
      providers: [],
      emergency_contacts: [],
      documents: [],
    ),
    MemberWithData(
      member: Member(
        id: 4,
        email: "",
        first_name: "Riley",
        last_name: "Johnson",
        date_of_birth: "2019-11-03",
        role: RegularMember,
        is_managed: True,
      ),
      allergies: [],
      medications: [],
      immunizations: [],
      insurance_policies: [],
      providers: [],
      emergency_contacts: [],
      documents: [],
    ),
  ]
}

pub fn get_member_by_id(id: Int) -> Option(MemberWithData) {
  list.find(all_members(), fn(mwd) { mwd.member.id == id })
  |> option.from_result()
}
