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
#
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

  robot.respond /set (.*) on rule (.*) with (.*)/i, (msg) ->
    argument = msg.match[1]
    rule_id = msg.match[2]
    values = msg.match[3].split(',')
    rules = get_rules()
    rules[rule_id][argument] = values
    set_rules(rules)

    msg.send get_rule_table()

  robot.respond /sanity check$/i, (msg) ->
    repo = "labemotes"
    base_url = process.env.HUBOT_GITHUB_API || 'https://api.github.com'
    url = "#{base_url}/repos/#{repo}/commits"

    github.get url, (commits) ->
      if commits.message
        msg.send "Achievement unlocked: [NEEDLE IN A HAYSTACK] repository #{commits.message}!"
      else if commits.length == 0
          msg.send "Achievement unlocked: [LIKE A BOSS] no commits found!"
      else
        msg.send "https://github.com/#{repo}"
        send = 5
        for c in commits
          if send
            d = new Date(Date.parse(c.commit.committer.date))
            msg.send "[#{d} -> #{c.commit.committer.name}] #{c.commit.message}"
            send -= 1

  robot.router.post '/web_ping', (req, res) ->
    res.send 'PONG'

  robot.router.post '/github_webhook', (req, res) ->
    event = req.get('X-Github-Event')
    console.log "Receieved GitHub Event: #{event}"

    if event == "issue_comment"
      comment_text = req.body.comment.body
      issue_labels_url = req.body.issue.labels_url.replace("{/name}", "")
      repo_labels_url = req.body.repository.labels_url.replace("{/name}", "")

      rules = get_rules()

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
    return "\n" + table.toString()

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




  # robot.hear /badger/i, (msg) ->
  #   msg.send "Badgers? BADGERS? WE DON'T NEED NO STINKIN BADGERS"
  #
  # robot.respond /open the (.*) doors/i, (msg) ->
  #   doorType = msg.match[1]
  #   if doorType is "pod bay"
  #     msg.reply "I'm afraid I can't let you do that."
  #   else
  #     msg.reply "Opening #{doorType} doors"
  #
  # robot.hear /I like pie/i, (msg) ->
  #   msg.emote "makes a freshly baked pie"
  #
  # lulz = ['lol', 'rofl', 'lmao']
  #
  # robot.respond /lulz/i, (msg) ->
  #   msg.send msg.random lulz
  #
  # robot.topic (msg) ->
  #   msg.send "#{msg.message.text}? That's a Paddlin'"
  #
  #
  # enterReplies = ['Hi', 'Target Acquired', 'Firing', 'Hello friend.', 'Gotcha', 'I see you']
  # leaveReplies = ['Are you still there?', 'Target lost', 'Searching']
  #
  # robot.enter (msg) ->
  #   msg.send msg.random enterReplies
  # robot.leave (msg) ->
  #   msg.send msg.random leaveReplies
  #
  # answer = process.env.HUBOT_ANSWER_TO_THE_ULTIMATE_QUESTION_OF_LIFE_THE_UNIVERSE_AND_EVERYTHING
  #
  # robot.respond /what is the answer to the ultimate question of life/, (msg) ->
  #   unless answer?
  #     msg.send "Missing HUBOT_ANSWER_TO_THE_ULTIMATE_QUESTION_OF_LIFE_THE_UNIVERSE_AND_EVERYTHING in environment: please set and try again"
  #     return
  #   msg.send "#{answer}, but what is the question?"
  #
  # robot.respond /you are a little slow/, (msg) ->
  #   setTimeout () ->
  #     msg.send "Who you calling 'slow'?"
  #   , 60 * 1000
  #
  # annoyIntervalId = null
  #
  # robot.respond /annoy me/, (msg) ->
  #   if annoyIntervalId
  #     msg.send "AAAAAAAAAAAEEEEEEEEEEEEEEEEEEEEEEEEIIIIIIIIHHHHHHHHHH"
  #     return
  #
  #   msg.send "Hey, want to hear the most annoying sound in the world?"
  #   annoyIntervalId = setInterval () ->
  #     msg.send "AAAAAAAAAAAEEEEEEEEEEEEEEEEEEEEEEEEIIIIIIIIHHHHHHHHHH"
  #   , 1000
  #
  # robot.respond /unannoy me/, (msg) ->
  #   if annoyIntervalId
  #     msg.send "GUYS, GUYS, GUYS!"
  #     clearInterval(annoyIntervalId)
  #     annoyIntervalId = null
  #   else
  #     msg.send "Not annoying you right now, am I?"
  #
  #
  # robot.router.post '/hubot/chatsecrets/:room', (req, res) ->
  #   room   = req.params.room
  #   data   = JSON.parse req.body.payload
  #   secret = data.secret
  #
  #   robot.messageRoom room, "I have a secret: #{secret}"
  #
  #   res.send 'OK'
  #
  # robot.error (err, msg) ->
  #   robot.logger.error "DOES NOT COMPUTE"
  #
  #   if msg?
  #     msg.reply "DOES NOT COMPUTE"
  #
  # robot.respond /have a soda/i, (msg) ->
  #   # Get number of sodas had (coerced to a number).
  #   sodasHad = robot.brain.get('totalSodas') * 1 or 0
  #
  #   if sodasHad > 4
  #     msg.reply "I'm too fizzy.."
  #
  #   else
  #     msg.reply 'Sure!'
  #
  #     robot.brain.set 'totalSodas', sodasHad+1
  #
  # robot.respond /sleep it off/i, (msg) ->
  #   robot.brain.set 'totalSodas', 0
  #   robot.respond 'zzzzz'
