import data/mock_members.{
  type Allergy, type Document, type EmergencyContact, type Immunization,
  type InsurancePolicy, type Medication, type MemberWithData, type Provider,
  type Role, Allergy, Document, EmergencyContact, Immunization, InsurancePolicy,
  Medication, MemberWithData, Provider,
}
import gleam/option.{type Option, None}

pub type EditTarget {
  EditingAllergy(id: Int)
  EditingMedication(id: Int)
  EditingImmunization(id: Int)
  EditingInsurance(id: Int)
  EditingProvider(id: Int)
  EditingEmergencyContact(id: Int)
  EditingDocument(id: Int)
  AddingAllergy
  AddingMedication
  AddingImmunization
  AddingInsurance
  AddingProvider
  AddingEmergencyContact
  AddingDocument
}

pub type Model {
  Model(
    member: MemberWithData,
    is_new: Bool,
    editing_item: Option(EditTarget),
    draft_first_name: String,
    draft_last_name: String,
    draft_email: String,
    draft_dob: String,
    draft_role: Role,
    draft_is_managed: Bool,
    draft_allergy: Allergy,
    draft_medication: Medication,
    draft_immunization: Immunization,
    draft_insurance: InsurancePolicy,
    draft_provider: Provider,
    draft_emergency_contact: EmergencyContact,
    draft_document: Document,
    next_id: Int,
  )
}

pub fn blank_member_with_data() -> MemberWithData {
  MemberWithData(
    member: mock_members.Member(
      id: 0,
      email: "",
      first_name: "",
      last_name: "",
      date_of_birth: "",
      role: mock_members.RegularMember,
      is_managed: False,
    ),
    allergies: [],
    medications: [],
    immunizations: [],
    insurance_policies: [],
    providers: [],
    emergency_contacts: [],
    documents: [],
  )
}

pub fn blank_allergy() -> Allergy {
  Allergy(id: 0, name: "", severity: "", notes: "")
}

pub fn blank_medication() -> Medication {
  Medication(
    id: 0,
    name: "",
    dosage: "",
    frequency: "",
    prescribing_provider: "",
  )
}

pub fn blank_immunization() -> Immunization {
  Immunization(
    id: 0,
    vaccine_name: "",
    date_administered: "",
    administered_by: "",
  )
}

pub fn blank_insurance() -> InsurancePolicy {
  InsurancePolicy(
    id: 0,
    provider_name: "",
    policy_number: "",
    group_number: "",
    plan_type: "",
  )
}

pub fn blank_provider() -> Provider {
  Provider(id: 0, name: "", specialty: "", phone: "", address: "")
}

pub fn blank_emergency_contact() -> EmergencyContact {
  EmergencyContact(id: 0, name: "", relationship: "", phone: "")
}

pub fn blank_document() -> Document {
  Document(id: 0, name: "", document_type: "", notes: "")
}

pub fn model_from_member_with_data(mwd: MemberWithData, is_new: Bool) -> Model {
  Model(
    member: mwd,
    is_new: is_new,
    editing_item: None,
    draft_first_name: mwd.member.first_name,
    draft_last_name: mwd.member.last_name,
    draft_email: mwd.member.email,
    draft_dob: mwd.member.date_of_birth,
    draft_role: mwd.member.role,
    draft_is_managed: mwd.member.is_managed,
    draft_allergy: blank_allergy(),
    draft_medication: blank_medication(),
    draft_immunization: blank_immunization(),
    draft_insurance: blank_insurance(),
    draft_provider: blank_provider(),
    draft_emergency_contact: blank_emergency_contact(),
    draft_document: blank_document(),
    next_id: 100,
  )
}
