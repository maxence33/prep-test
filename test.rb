require "tty-markdown"
require "timeout"

class Test
  attr_reader :questions, :answers, :howto

  DURATION = 60 * 90

  class Exit < StandardError; end

  class EndOfTime < StandardError; end

  def initialize(type: :silver, language: :en, start_position: 1, end_position: 50)
    
    @start_pos = start_position
    @end_pos = end_position
    validate_positions

    # Basically we split both questions and answers file based on ^------------- string
    file_reader = proc { |file_name|
      File.read("#{file_name}#{(language == :en) ? "" : "_ja"}.md").split(/^-------------.*\n/)[0..49]
    }

    # Will identify the answers line, scan the results and transpile into an array 
    # (a) (b) => [0, 2]
    # (A) (C) => [0, 3]
    answer_parser = proc { |answer| 
      answer.slice(/^\*\*A\d+[:.].*/).scan(/\(([a-zA-Z])\)/).flatten(1).map { |i|
          i.downcase.ord - "a".ord
        }
    }

    @questions = file_reader.call type
    @answers = file_reader.call "#{type}_answers"
    @answers.map! do |ans|
      answer_parser.call ans
    end
    
    @howto = File.read("test_readme.md")
    @last_printed_lines_count = 0

  end

  Signal.trap("INT") do
    puts "Are you sure want to quit? (Enter `yes` to exit)"
    if gets.match?(/(yes|y)/i)
      raise Exit
    else
      puts "Back to Test - Type your answer"
    end
  end

  def start
    clean_the_screen
    print_howto
    clean_the_screen
    Timeout.timeout(DURATION, EndOfTime) do
      @exam_started = true
      exam
    end
  rescue Exit
    clean_the_screen
    calc_and_print_result(@result)
  rescue EndOfTime
    clean_the_screen
    puts "# Time for exam has runned out"
    calc_and_print_result(@result)
  end

  private

  def exam
    @curr_inx = @start_pos-2
    @result = Array.new(50)
    @user_answers = Array.new(50)
    loop do
      @curr_inx += 1 
      show_question
      user_input = get_user_input
      case user_input
      when :repeat
        @curr_inx -= 1
        next
      when :next
        next
      when :prev
        @curr_inx -= 2
        next
      when :howto
        @curr_inx -= 1
        clean_the_screen
        print_howto
        clean_the_screen
      else
        @user_answers[@curr_inx] = user_input
        @result[@curr_inx] = validate_answer(user_input)
      end
    end
  end

  def show_question
    raise Exit if @curr_inx == @end_pos 
    clean_the_screen
    question = questions[@curr_inx]
    puts question
    if @user_answers[@curr_inx]
      prev_answ = @user_answers[@curr_inx].map { |i| ("a".ord + i).chr }.join(",")
      puts "## Your previously entered answer is **(#{prev_answ})**"
    end
  end

  def validate_answer(user_answers)
    user_answers.sort == answers[@curr_inx].sort
  end

  def get_user_input
    puts "**Write you answers separated by commas:**"
    user_answer = gets.chomp
    case user_answer
    in /exit/i
      puts "**Are you sure want finish exam? (Enter `yes` to exit)**"
      raise Exit if gets.match?(/(yes|y)/i)

      :repeat
    in /\A(n|next|continue)\z/i
      :next
    in /\A(p|previous|prev\z)/i
      :prev
    in /\Agoto (\d+)\z/
      return :repeat unless $1.to_i.between?(@start_pos, @end_pos)

      @curr_inx = $1.to_i - 1
      :repeat
    in /\A(stop|finish|end\z)/i
      puts "**Are you sure want finish exam? (Enter `yes` to exit)**"
      raise Exit if gets.match?(/(yes|y)/i)

      :repeat
    in /\A(help|h)\z/i
      puts <<~MD
        # Available commands
        - `howto` - print the text that was printend at start (don't restart the exam)
        - `n` or `next` or `continue` - to go to the next question in order
        - `p` or `prev` or `previous` - to go to the previous question in order
        - `stop` or `finish` or `end` - to finish the exam and print your results
        - `h` or `help` - to print this text

        **Press enter to continue**
      MD
      gets

      :repeat
    in /\Ahowto\z/i
      :howto
    else
      user_answer.strip.split(",").map { |e| e.downcase.ord - "a".ord }
    end
  end

  def calc_and_print_result(result)
    
    if !result
      puts "No result available, you haven't answered any question" 
      return
    end

    correct_answers_count = result.count { |e| 1 if e }
    correct_answers_ids = result.map.with_index{ |e,i| !e ? i : nil }.compact
    numbered_of_answered_questions = result.compact.count
    correct_answers_percent = correct_answers_count.to_f / questions.length * 100
    
    puts "Your result is **#{correct_answers_count} out of #{questions.length}** total questions"
    puts "You answered correctly **#{correct_answers_count} out of #{numbered_of_answered_questions}** answered questions"
    puts "You failed these questions: **#{correct_answers_ids.join(", ")}**."
    puts "Percent of **correct answers is #{correct_answers_percent.round(2)}%**"

    if correct_answers_count >= 75.0
      puts "## You've passed the test exam"
    else
      puts "## You've failed the test exam."
      puts "### Don't give up! You can do it! (="
    end
  end

  def print_howto
    puts howto.to_s
    if @exam_started
      puts "**Press enter to continue**"
      gets
    else
      puts "## To start the test enter `y`"
      raise Exit unless gets.chomp.match?(/\Ay\z/)
    end
  end

  def clean_the_screen
    print "\033[2J\033[3J\033[1;1H"
  end

  def puts(string)
    Kernel.puts TTY::Markdown.parse(string).to_s
  end

  def validate_positions
    raise ArgumentError, "Start position must be less than end position." if @start_pos >= @end_pos

    unless (1..50).include?(@start_pos) && (1..50).include?(@end_pos)
      raise ArgumentError, "Positions must be between 1 and 50."
    end
  end
end

positional_args = ARGV.select{|arg| !arg.match?(/=/)}
test_type = positional_args.fetch(0) {:silver}.to_sym 
test_language = positional_args.fetch(1) {:en}.to_sym 

keyworded_args = ARGV.select{|arg| arg.match?(/=/)}.map{|ary| ary.split("=")}.to_h
start_position = keyworded_args.fetch("start") {1}.to_i
end_position = keyworded_args.fetch("end") {50}.to_i

ARGV.clear
if test_type.match?("help")
  puts TTY::Markdown.parse(File.read("test_help.md")).to_s
else
  test = Test.new(type: test_type, language: test_language, start_position: start_position, end_position: end_position)
  test.start
end
