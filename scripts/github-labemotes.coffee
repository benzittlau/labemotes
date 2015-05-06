# Description:
#   Will add or remove labels on a github pull request based on text in a comment
#
# Dependencies:
#   "q": "*"
#   "githubot": "0.4.x"
#   "cli-table": "*"
#
# Configuration:
#   HUBOT_GITHUB_TOKEN
#   HUBOT_GITHUB_USER
#
# Commands:
#   hubot labemotes rules - Will output a table of the current labemotes rules
#   hubot reset labemotes rules - Will reset the labemotes rules back to default
#   hubot add labemotes rule - Will create a new blank labemote rule
#   hubot set <attribute> on labemote rule <rule_id> with <csv of value> - Updates a labemote rule attributge
#
# Author:
#   benzittlau
#

Q = require "q"

module.exports = (robot) ->
  github = require("githubot")(robot)

  robot.respond /labemotes.*rules/i, (msg) ->
    msg.send get_rule_table()

  robot.respond /reset.*labemotes.*rules/i, (msg) ->
    reset_rules()
    msg.send get_rule_table()

  robot.respond /(add|create) labemotes rule/i, (msg) ->
    rules = get_rules()
    rules.push {matches: [], add_labels: [], remove_labels: []}
    set_rules(rules)
    msg.send get_rule_table()

  robot.respond /set (.*) on labemote rule (.*) with (.*)/i, (msg) ->
    argument = msg.match[1]
    rule_id = msg.match[2]
    values = msg.match[3].split(',')
    rules = get_rules()
    rules[rule_id][argument] = values
    set_rules(rules)

    msg.send get_rule_table()

  robot.router.post '/github_webhook', (req, res) ->
    event = req.get('X-Github-Event')
    console.log "Receieved GitHub Event: #{event}"

    if event == "issue_comment"
      comment_text = req.body.comment.body
      issue_labels_url = req.body.issue.labels_url.replace("{/name}", "")
      repo_labels_url = req.body.repository.labels_url.replace("{/name}", "")

      rules = get_rules()

      escape_regex = new RegExp(':no_entry:', 'i')
      if !escape_regex.test(comment_text)
        applicable_rules = rules.filter (rule) ->
          escaped_matches = rule.matches.map (match) -> match.replace(/[-\/\\^$*+?.()|[\]{}]/g, '\\$&')
          regex = new RegExp(escaped_matches.join('|'), 'i')

          regex.test(comment_text)

        Q.all([
          get_labels(issue_labels_url),
          get_labels(repo_labels_url),
          issue_labels_url,
          applicable_rules[0]
        ]).spread(update_issue_labels)

      res.send 'PONG'
    else
      res.send(501)


  reset_rules = ->
    rules = [
      {
        matches: ['approved', ':+1:']
        add_labels: ['APPROVED'],
        remove_labels: ['COMMENTS', 'NEEDS_DISCUSSION']},
      {
        matches: ['changes required', ':notebook:']
        add_labels: ['COMMENTS'],
        remove_labels: ['APPROVED']
      }
    ]
    set_rules(rules)

    return rules

  get_rule_table = ->
    Table = require('cli-table')
    table = new Table({head: ['id', 'matches', 'add_labels', 'remove_labels']})
    rules = get_rules()
    i = 0
    for rule in rules
      table.push([i++, rule.matches.join("\n"), rule.add_labels.join("\n"), rule.remove_labels.join("\n")])
    return "``` " + table.toString() + " ```"

  get_rules = ->
    raw_rules = robot.brain.get('rules')
    return if raw_rules? then JSON.parse(raw_rules) else reset_rules()

  set_rules = (rules) ->
    return robot.brain.set('rules', JSON.stringify(rules))

  get_labels = (url) ->
    deferred = Q.defer()
    github = require('githubot')(robot)

    github.get url, (labels) ->
      deferred.resolve(labels)

    return deferred.promise

  set_labels = (url, labels) ->
    deferred = Q.defer()
    github = require('githubot')(robot)

    label_data = labels.map (label) -> label.name
    console.log("Applying labels to pull request #{JSON.stringify(label_data)}.")

    github.put url, label_data, (result) ->
      deferred.resolve(result)

    return deferred.promise


  update_issue_labels = (current_labels, repo_labels, label_url, rule) ->
    remove_labels = rule.remove_labels
    add_labels = rule.add_labels
    current_labels_to_keep = current_labels.filter (label) ->
      label.name not in remove_labels

    repo_labels_to_add = repo_labels.filter (label) ->
      label.name in add_labels

    labels_to_set = current_labels_to_keep.concat repo_labels_to_add

    set_labels(label_url, labels_to_set)
