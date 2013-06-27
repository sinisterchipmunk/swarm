#!/usr/bin/env ruby

begin
  require 'bundler/setup'
  require 'AWS'
  require 'yaml'
  require 'net/ssh'
rescue LoadError
  puts "Could not load a required dependency."
  puts
  puts "Run `bundle install` and then try again."
  exit
end

if ARGV.length != 2
  puts "Usage: swarm [N] [CMD]"
  puts
  puts "N   - The number of concurrent executions PER BEE"
  puts "CMD - the command(s) to execute"
  puts
  exit
end

CONCURRENCY = ARGV[0].to_i
COMMAND     = ARGV[1]

swarm_config = File.expand_path("~/.swarm")
bees_config  = File.expand_path('~/.bees')

yaml = {}
yaml = YAML::load(File.read(swarm_config)) if File.exist?(swarm_config)

ACCESS_KEY_ID     = ENV['AWS_ACCESS_KEY_ID']     || yaml['AWS_ACCESS_KEY_ID']
SECRET_ACCESS_KEY = ENV['AWS_SECRET_ACCESS_KEY'] || yaml['AWS_SECRET_ACCESS_KEY']

aws = AWS::EC2::Base.new(access_key_id: ACCESS_KEY_ID,
                         secret_access_key: SECRET_ACCESS_KEY)

bees = File.read(bees_config).lines.to_a
USERNAME = bees[0].chomp
SSH_KEY = bees[1].chomp
instance_ids = bees[2..-1]

instances = aws.describe_instances(instance_ids: instance_ids)
IPS = []

instances['reservationSet']['item'][0]['instancesSet']['item'].each do |instance|
  IPS.push instance['privateDnsName']
end

THREADS = []
def ssh_recursive
  return unless ip = IPS.pop
  THREADS << Thread.new do
    puts "Connecting to #{ip}"

    Net::SSH.start(ip, USERNAME, keys: [File.expand_path('~/.ssh/%s.pem' % SSH_KEY)]) do |ssh|
      ssh_recursive

      cmd = "rm -rf swarm; mkdir swarm; cd swarm; "
      CONCURRENCY.times do |i|
        cmd << "mkdir #{i}; cd #{i}; #{COMMAND} &"
      end

      begin
        ssh.exec cmd do |ch, stream, data|
          if stream == :stderr
            puts "ERROR: #{data}"
          else
            puts data
          end
        end

        ssh.loop
      rescue
        puts "FAILURE ON #{ip}: #{$!.message}"
      end
    end
  end
end

ssh_recursive

THREADS.each { |th| th.join }