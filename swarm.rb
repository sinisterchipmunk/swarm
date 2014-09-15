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

unless [2, 3].include? ARGV.length
  puts "Usage: swarm [N] [CMD] [BEFORE]"
  puts
  puts "N      - The number of concurrent executions PER BEE"
  puts "CMD    - the command to execute"
  puts "BEFORE - optional command(s) to execute during the setup phase"
  puts
  exit
end

CONCURRENCY = ARGV[0].to_i
COMMAND     = ARGV[1]
BEFORE      = ARGV[2] || ""

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
instance_ids = bees[2..-1].collect { |i| i.chomp }

#instances = aws.describe_instances(instance_ids: instance_ids)
require 'pp'
IPS = []

#instances['reservationSet']['item'].each do |set|
#  set['instancesSet']['item'].each do |instance|
#    next unless instance_ids.include?(instance['instanceId'])
#    IPS.push instance['dnsName'] #instance['privateDnsName']
#  end
#end

`bees report | grep "running " | cut -d ' ' -f 5`.lines.each do |line|
  IPS << line.chomp
end

puts "IPs : #{IPS.inspect}"

THREADS = []

cmd = [
  'rm -rf swarm',
  'mkdir swarm',
  'cd swarm'
]

cmd.concat [
  "for RUN in #{CONCURRENCY.times.to_a.join(' ')}",
  "do",
    "mkdir $RUN",
    "cd $RUN",
    BEFORE,
    "cd ..",
  "done"
]

cmd.concat [
  "for RUN in #{CONCURRENCY.times.to_a.join(' ')}",
  "do",
    "cd $RUN",
    "#{COMMAND} &",
    "export WAITFOR=\"$WAITFOR $! \"",
    "cd ..",
  "done"
]

cmd.concat [
  'for i in $WAITFOR',
  'do',
    'wait $i',
  'done'
]

CMD = "bash <<-end_cmd\n#{cmd.join("\n").gsub(/\$/, '\\$')}\nend_cmd\n"

def ssh_recursive
  return unless ip = IPS.pop
  THREADS << Thread.new do
    puts "Connecting to #{USERNAME}@#{ip} with ~/.ssh/#{SSH_KEY}.pem"

    Net::SSH.start(ip, USERNAME, keys: [File.expand_path('~/.ssh/%s.pem' % SSH_KEY)]) do |ssh|
      ssh_recursive

      begin
        ssh.exec CMD do |ch, stream, data|
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
p 'done'
