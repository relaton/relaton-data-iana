# frozen_string_literal: true

require 'fileutils'

FileUtils.rm_rf('data')

t1 = Time.now
puts "Started at: #{t1}"

system("relaton fetch-data iana-registries")

t2 = Time.now
puts "Stopped at: #{t2}"
puts "Done in: #{(t2 - t1).round} sec."
