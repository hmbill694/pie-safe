import gleam/int
import gleam/option.{None, Some}
import gleam/uri.{type Uri}
import lustre
import lustre/attribute
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/element/html
import modem
import pages/home
import pages/member_detail
import pages/sign_in
import pages/sign_up

pub type Route {
  SignUp
  SignIn
  Home
  MemberDetail(id: Int)
  NewMember
}

pub type Model {
  Model(
    route: Route,
    sign_up: sign_up.Model,
    sign_in: sign_in.Model,
    home: home.Model,
    member_detail: member_detail.Model,
  )
}

pub type Msg {
  OnRouteChange(Route)
  SignUpMsg(sign_up.Msg)
  SignInMsg(sign_in.Msg)
  HomeMsg(home.Msg)
  MemberDetailMsg(member_detail.Msg)
}

fn parse_route(current_uri: Uri) -> Route {
  case uri.path_segments(current_uri.path) {
    ["sign-up"] -> SignUp
    ["sign-in"] -> SignIn
    ["home"] -> Home
    ["members", "new"] -> NewMember
    ["members", id_str] ->
      case int.parse(id_str) {
        Ok(id) -> MemberDetail(id)
        Error(_) -> SignIn
      }
    _ -> SignIn
  }
}

fn on_url_change(current_uri: Uri) -> Msg {
  OnRouteChange(parse_route(current_uri))
}

pub fn init(_flags) -> #(Model, Effect(Msg)) {
  let initial_route = case modem.initial_uri() {
    Ok(current_uri) -> parse_route(current_uri)
    Error(_) -> SignIn
  }
  let #(home_model, home_effect) = home.init()
  let #(member_detail_model, member_detail_effect) = member_detail.init(None)
  let model =
    Model(
      route: initial_route,
      sign_up: sign_up.init(),
      sign_in: sign_in.init(),
      home: home_model,
      member_detail: member_detail_model,
    )
  let effects =
    effect.batch([
      modem.init(on_url_change),
      effect.map(home_effect, HomeMsg),
      effect.map(member_detail_effect, MemberDetailMsg),
    ])
  #(model, effects)
}

pub fn update(model: Model, msg: Msg) -> #(Model, Effect(Msg)) {
  case msg {
    OnRouteChange(route) -> {
      case route {
        Home -> {
          let #(home_model, home_effect) = home.init()
          #(
            Model(..model, route: route, home: home_model),
            effect.map(home_effect, HomeMsg),
          )
        }
        MemberDetail(id) -> {
          let #(md_model, md_effect) = member_detail.init(Some(id))
          #(
            Model(..model, route: route, member_detail: md_model),
            effect.map(md_effect, MemberDetailMsg),
          )
        }
        NewMember -> {
          let #(md_model, md_effect) = member_detail.init(None)
          #(
            Model(..model, route: route, member_detail: md_model),
            effect.map(md_effect, MemberDetailMsg),
          )
        }
        _ -> #(Model(..model, route: route), effect.none())
      }
    }
    SignUpMsg(sub_msg) -> {
      let #(sub_model, sub_effect) = sign_up.update(model.sign_up, sub_msg)
      #(Model(..model, sign_up: sub_model), effect.map(sub_effect, SignUpMsg))
    }
    SignInMsg(sub_msg) -> {
      let #(sub_model, sub_effect) = sign_in.update(model.sign_in, sub_msg)
      #(Model(..model, sign_in: sub_model), effect.map(sub_effect, SignInMsg))
    }
    HomeMsg(sub_msg) -> {
      let #(sub_model, sub_effect) = home.update(model.home, sub_msg)
      #(Model(..model, home: sub_model), effect.map(sub_effect, HomeMsg))
    }
    MemberDetailMsg(sub_msg) -> {
      let #(sub_model, sub_effect) =
        member_detail.update(model.member_detail, sub_msg)
      #(
        Model(..model, member_detail: sub_model),
        effect.map(sub_effect, MemberDetailMsg),
      )
    }
  }
}

pub fn view(model: Model) -> Element(Msg) {
  html.div([attribute.class("min-h-screen bg-gray-50")], [
    case model.route {
      SignUp -> element.map(sign_up.view(model.sign_up), SignUpMsg)
      SignIn -> element.map(sign_in.view(model.sign_in), SignInMsg)
      Home -> element.map(home.view(model.home), HomeMsg)
      MemberDetail(_) ->
        element.map(member_detail.view(model.member_detail), MemberDetailMsg)
      NewMember ->
        element.map(member_detail.view(model.member_detail), MemberDetailMsg)
    },
  ])
}

pub fn main() {
  let app = lustre.application(init, update, view)
  let assert Ok(_) = lustre.start(app, "#app", Nil)
  Nil
}
