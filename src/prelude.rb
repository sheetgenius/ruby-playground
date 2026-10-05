require "js"

module KidPlayground
  MAX_LINES = 2000

  # Words a beginner is likely reaching for, offered first in "Did you mean" hints.
  KID_WORDS = %w[
    puts print gets sleep rand loop exit times upto downto each map reverse upcase downcase
    capitalize length size chomp to_i to_s first last sort sum new include? empty?
  ].freeze

  # Raised when a program prints too much. It is not a StandardError,
  # so a plain `rescue` in a program can't swallow it.
  class TooMuchOutput < Exception; end

  # Stands in for $stdout and $stderr and sends every write to the page.
  class Screen
    def initialize(stream)
      @stream = stream
    end

    def write(*parts)
      parts.sum do |part|
        text = part.to_s
        next 0 if text.empty?

        KidPlayground.count_lines(text)
        JS.global.call(:kidWrite, @stream, text)
        text.bytesize
      end
    end

    def puts(*items)
      if items.empty?
        write("\n")
        return nil
      end
      items.each do |item|
        if item.is_a?(Array)
          item.empty? ? write("\n") : item.flatten.each { |inner| puts(inner) }
        else
          text = item.nil? ? "" : item.to_s
          write(text.end_with?("\n") ? text : "#{text}\n")
        end
      end
      nil
    end

    def print(*items)
      items.each { |item| write(item) }
      nil
    end

    def printf(format_string, *values)
      write(format(format_string, *values))
      nil
    end

    def <<(text)
      write(text)
      self
    end

    def flush = self
    def sync = true
    def sync=(_value); end
    def tty? = false
    def isatty = false
    def fileno = (@stream == "err" ? 2 : 1)
  end

  # Stands in for $stdin.
  class Keyboard
    def gets(*) = KidPlayground.ask
    def readline(*) = KidPlayground.ask
  end

  @lines = 0

  def self.count_lines(text)
    @lines += text.count("\n")
    raise TooMuchOutput if @lines > MAX_LINES
  end

  def self.ask
    answer = JS.global.call(:kidAsk).await.to_s
    "#{answer}\n"
  end

  def self.pause(seconds)
    seconds = 1 if seconds.nil?
    started = Time.now
    JS.global.call(:kidSleep, (seconds.to_f * 1000).round).await
    (Time.now - started).round
  end

  def self.run(code)
    TOPLEVEL_BINDING.eval(code, "my_code.rb", 1)
  rescue SystemExit
    # The program called exit, which is a normal way to finish.
  rescue TooMuchOutput
    JS.global.call(:kidTooMuch)
  rescue Exception => error
    report(error)
  end

  def self.report(error)
    receiver = error.is_a?(NoMethodError) ? describe(error.receiver) : ""
    name = error.is_a?(NameError) ? error.name.to_s : ""
    suggestions = error.is_a?(NameError) ? suggestions_for(error).join(" ") : ""
    JS.global.call(:kidError, error.class.name.to_s, error.message.to_s, error_line(error), name, receiver, suggestions)
  rescue Exception
    JS.global.call(:kidError, error.class.name.to_s, error.message.to_s, 0, "", "", "")
  end

  # A small stand-in for the did_you_mean gem, which this Ruby build leaves out.
  def self.suggestions_for(error)
    word = error.name.to_s
    return [] if word.empty?

    main = TOPLEVEL_BINDING.receiver
    pool =
      if error.is_a?(NoMethodError) && !error.receiver.equal?(main)
        error.receiver.methods
      else
        error.local_variables + KID_WORDS + main.private_methods + main.methods
      end
    pool += Object.constants if word.match?(/\A[A-Z]/)
    limit = word.length > 5 ? 2 : 1
    pool.map(&:to_s).uniq
        .reject { |name| name == word }
        .map { |name| [distance(word.downcase, name.downcase), KID_WORDS.include?(name) ? 0 : 1, name] }
        .select { |score, _, _| score <= limit }
        .sort
        .first(2)
        .map(&:last)
  rescue Exception
    []
  end

  # Edit distance where swapping two neighboring letters counts as one edit.
  def self.distance(left, right)
    rows = Array.new(left.length + 1) { |row| Array.new(right.length + 1) { |column| row.zero? ? column : (column.zero? ? row : 0) } }
    (1..left.length).each do |row|
      (1..right.length).each do |column|
        cost = left[row - 1] == right[column - 1] ? 0 : 1
        best = [rows[row - 1][column] + 1, rows[row][column - 1] + 1, rows[row - 1][column - 1] + cost].min
        if row > 1 && column > 1 && left[row - 1] == right[column - 2] && left[row - 2] == right[column - 1]
          best = [best, rows[row - 2][column - 2] + 1].min
        end
        rows[row][column] = best
      end
    end
    rows[left.length][right.length]
  end

  def self.error_line(error)
    text = error.is_a?(SyntaxError) ? error.message : Array(error.backtrace).join("\n")
    text[/my_code\.rb:(\d+)/, 1].to_i
  end

  def self.describe(object)
    case object
    when nil then "nil"
    when Integer, Float then "the number #{object}"
    when String then "the words #{object.inspect[0, 30]}"
    when Symbol then "the symbol #{object.inspect}"
    when Array then "a list"
    when Hash then "a hash"
    when true, false then object.to_s
    else
      object.equal?(TOPLEVEL_BINDING.receiver) ? "main" : "a #{object.class.name}"
    end
  rescue Exception
    ""
  end
end

module Kernel
  private

  def gets(*) = KidPlayground.ask
  def readline(*) = KidPlayground.ask
  def sleep(seconds = nil) = KidPlayground.pause(seconds)
  # The usual pp lives in a library this Ruby build leaves out.
  def pp(*items) = p(*items)
end

$stdout = KidPlayground::Screen.new("out")
$stderr = KidPlayground::Screen.new("err")
$stdin = KidPlayground::Keyboard.new

# STDOUT and friends would still point at the hidden real streams.
{ STDOUT: $stdout, STDERR: $stderr, STDIN: $stdin }.each do |name, stream|
  Object.send(:remove_const, name)
  Object.const_set(name, stream)
end
