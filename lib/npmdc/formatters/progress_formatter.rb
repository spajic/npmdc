module Npmdc
  module Formatters
    class ProgressFormatter < BaseFormatter
      def dep_output(_dep, status)
        case status
        when :success
          @output.print color_message(".", status)
        when :failure
          @output.print color_message("F", status)
        end
      end

      def check_finish_output
        2.times { @output.puts "\n" }
      end
    end
  end
end