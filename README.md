# swarm

A script I hacked together to help me load test stuff. It relies on
[bees with machine guns](https://github.com/newsapps/beeswithmachineguns)
for setup and teardown.

## Usage

    # Install dependencies. You need Ruby first.
    bundle install

    # Spin up the servers using bees.
    bees up -s 4 -g public -k frakkingtoasters

    # Now use swarm:
    ./swarm.rb 100 "git clone http://server.com/git-repos/honey.git"

    # Spin down with bees, or pay lots of money -- your choice.
    bees down

## Explanation

In the example above, "100" is the number of _concurrent executions per server_
that will be made. Since in this example we are using 4 servers, a total
of 400 git clones will be performed simultaneously.

The second argument is an arbitrary command to run. In this example we did
a git clone from a server we intend to serve git repos from.
