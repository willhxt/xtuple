// Contributions of status related functionality borrowed from SproutCore:
// https://github.com/sproutcore/sproutcore

/*jshint trailing:true, white:true, indent:2, strict:true, curly:true, plusplus:true
  immed:true, eqeqeq:true, forin:true, latedef:true, newcap:true, noarg:true, undef:true */
/*jslint bitwise: true, nomen: true, indent:2 */
/*global XT:true, Backbone:true, _:true, console:true, setTimeout: true */

(function () {
  "use strict";

  //...........................................
  // THE FOLLOWING IMPLEMENTATION IS VERY TEMPORARY
  // FOR DEVELOPMENT PURPOSES ONLY!
  XT.locale = {
    hasStrings: false,
    strings: {},
    lang: "",

    getHasStrings: function () {
      return this.hasStrings;
    },

    getLang: function () {
      return this.lang;
    },

    getStrings: function () {
      return this.strings;
    },

    setHasStrings: function (value) {
      this.hasStrings = value;
      return this;
    },

    setLang: function (value) {
      this.lang = value;
      return this;
    },

    setStrings: function (value) {
      this.strings = value;
      return this;
    },

    setLanguage: function (language) {
      if (this.getHasStrings()) {
        return console.log("attempt to set a new language");
      }
      this.setLang(language.lang || "en");
      this.setStrings(language.strings || {});
    },

    stringsChanged: function () {
      var strings = this.getStrings();
      if (strings && strings instanceof Object && Object.keys(strings).length > 0) {
        this.setHasStrings(true);
      } else { this.error("something is amiss"); }
    },

    loc: function (str) {
      var strings = this.getStrings();
      return strings[str] || str.toString();
    }

  };

  XT.stringsFor = function (lang, stringsHash) {
    if (!XT.lang) {
      XT.lang = {
        lang: lang,
        strings: stringsHash
      };
    } else {
      console.log("XT.stringsFor(): request to write over current language");
    }
  };

}());