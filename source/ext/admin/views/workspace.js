/*jshint bitwise:true, indent:2, curly:true eqeqeq:true, immed:true,
latedef:true, newcap:true, noarg:true, regexp:true, undef:true,
trailing:true white:true*/
/*global XT:true, XM:true, XV:true, enyo:true*/

(function () {

  // ..........................................................
  // USER
  //

  enyo.kind({
    name: "XV.UserWorkspace",
    kind: "XV.Workspace",
    title: "_user".loc(),
    components: [
      {kind: "Panels", arrangerKind: "CarouselArranger",
        fit: true, components: [
        {kind: "XV.Groupbox", name: "mainPanel", components: [
          {kind: "onyx.GroupboxHeader", content: "_overview".loc()},
          {kind: "XV.ScrollableGroupbox", name: "mainGroup", fit: true,
            classes: "in-panel", components: [
            {kind: "XV.InputWidget", attr: "id"},
            {kind: "onyx.Button", name: "resetPasswordButton", content: "_resetPassword".loc(), ontap: "resetPassword"}
          ]}
        ]},
        {kind: "XV.UserOrganizationsBox", attr: "organizations"}
      ]}
    ],
    model: "XM.User",
    resetPassword: function (inSender, inEvent) {
      console.log("Todo: reset password");
    }
  });

  XV.registerModelWorkspace("XM.User", "XV.UserWorkspace");

  // ..........................................................
  // DATABASE SERVER
  //

  enyo.kind({
    name: "XV.DatabaseServerWorkspace",
    kind: "XV.Workspace",
    title: "_databaseServer".loc(),
    components: [
      {kind: "Panels", arrangerKind: "CarouselArranger",
        fit: true, components: [
        {kind: "XV.Groupbox", name: "mainPanel", components: [
          {kind: "onyx.GroupboxHeader", content: "_overview".loc()},
          {kind: "XV.ScrollableGroupbox", name: "mainGroup", fit: true,
            classes: "in-panel", components: [
            {kind: "XV.InputWidget", attr: "name"},
            {kind: "XV.InputWidget", attr: "description"},
            {kind: "XV.InputWidget", attr: "hostname"},
            {kind: "XV.NumberWidget", attr: "port"}, // TODO: number formatting with a comma looks funny here
            {kind: "XV.InputWidget", attr: "location"},
            {kind: "XV.DateWidget", attr: "dateAdded"}, // TODO: should not be editable
            {kind: "XV.InputWidget", attr: "user"},
            {kind: "XV.InputWidget", attr: "password", type: "password"}
          ]}
        ]}
      ]}
    ],
    model: "XM.DatabaseServer"
  });

  XV.registerModelWorkspace("XM.DatabaseServer", "XV.DatabaseServerWorkspace");

  // ..........................................................
  // ORGANIZATION
  //

  enyo.kind({
    name: "XV.OrganizationWorkspace",
    kind: "XV.Workspace",
    title: "_organization".loc(),
    components: [
      {kind: "Panels", arrangerKind: "CarouselArranger",
        fit: true, components: [
        {kind: "XV.Groupbox", name: "mainPanel", components: [
          {kind: "onyx.GroupboxHeader", content: "_overview".loc()},
          {kind: "XV.ScrollableGroupbox", name: "mainGroup", fit: true,
            classes: "in-panel", components: [
            {kind: "XV.InputWidget", attr: "name"},
            {kind: "XV.InputWidget", attr: "description"},
            {kind: "XV.DatabaseServerWidget", attr: "databaseServer"}
          ]}
        ]}
      ]}
    ],
    model: "XM.Organization"
  });

  XV.registerModelWorkspace("XM.Organization", "XV.OrganizationWorkspace");



}());
