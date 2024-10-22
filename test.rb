require "tty-markdown"
require "timeout"

class Test
  attr_reader :questions, :answers, :howto

  DURATION = 60 * 90

  class Exit < StandardError; end

  class EndOfTime < StandardError; end

  def initialize(type: :silver, language: :en, start_position: 1, test_length: 50)
    
    @test_start = start_position-1
    @test_length = test_length-1

    # Basically we split both questions and answers file based on ^------------- string
    file_splitter = proc { |file_name|
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

    case type
    when :silver
      @questions = file_splitter.call "silver"
      @answers = file_splitter.call "silver_answers"
      @answers.map! do |ans|
        answer_parser.call ans
      end
    when :gold
      @questions = file_splitter.call "gold"
      @answers = file_splitter.call "gold_answers"
      @answers.map! do |ans|
        answer_parser.call ans
      end
    else
      raise StandardError, "test not found"
    end
    @howto = File.read("test_readme.md")
    @last_printed_lines_count = 0
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
    @curr_inx = -1
    @result = Array.new(50)
    @user_answers = Array.new(50)
    loop do
      next_question
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

  def next_question
    @curr_inx += 1 if @curr_inx < 49
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
      return :repeat unless $1.to_i.between?(1, 50)

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
end

test_type = ARGV[0]&.to_sym || :silver
test_language = ARGV[1]&.to_sym || :en
start_position = ARGV[2]&.to_i || 1
test_length = ARGV[3]&.to_i || 50
# need validate ARGV[2..3]


ARGV.clear
if test_type.match?("help")
  puts TTY::Markdown.parse(File.read("test_help.md")).to_s
else
  test = Test.new(type: test_type, language: test_language, start_position: start_position, test_length: test_length)
  test.start
end
