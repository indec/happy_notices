#!/usr/bin/env perl

use utf8;
use strict;
use warnings;
use Net::Twitter;
use Config::Tiny;

my $config_file = $ARGV[0];
if (!-e $config_file) {
    print "Usage: perl happy.pl config_file\n";
    exit;
}

my $config = Config::Tiny->read($config_file);

my $auth = $config->{auth};
my $twitter = Net::Twitter->new(
    traits => [qw(WrapError OAuth API::REST API::Search)],
    consumer_key => $auth->{consumer_key},
    consumer_secret => $auth->{consumer_secret},
    access_token => $auth->{access_token},
    access_token_secret => $auth->{access_token_secret},
);

# Basic options
# The search is a substring of the target, because apparently two single quotes
# in a query string break the search API. We can filter later.
my %opts = (
    q => "if this isn't nice",
    rpp => $config->{search}->{rpp},
    result_type => 'recent',
    page => 1,
);

# If we've run before, there should be a file with the last ID we saw.
# Only pull tweets later than that.
my $state_file = $config->{state}->{store};
if (-e $state_file) {
    open STATE, $config->{state}->{store} or die "Can't open $state_file: $!";
    $opts{since_id} = <STATE>;
    chomp $opts{since_id};
    close STATE;
}

my $results_count = $opts{rpp}; # convenient for while loop
my $since_id;

# Honestly, this loop really isn't necessary unless there's a sudden outbreak of
# happiness amongst Vonnegut fans. If the cron runs hourly, you get one or two tweets
# at most.
while ($results_count > 0) {
    my $results = $twitter->search(\%opts);
    $results_count = scalar @{$results->{results}};
    if ($results_count == 0) {
        # Nothing to do here, move along.
        exit;
    }
    if (!defined $since_id) {
        # First iteration of the loop, with the most recent tweet in it.
        # Stash the ID for the next run.
        $since_id = $results->{results}->[0]->{id};
        open OUT, ">$state_file" or die "Can't write $state_file: $!";
        print OUT $since_id;
        close OUT;
    }
    for (@{$results->{results}}) {
        # We're going to ignore case and punctuation.
        my $text = lc($_->{text});
        my $stripped = $text;
        $stripped =~ s/[^a-z ]//g;
        if (index($stripped, 'if this isnt nice i dont know what is') > -1) {
            # But we want to avoid RTs and references to others
            if ($text !~ /^\W*@/ && $text !~ /rt @/) {
                # And quotes of Vonnegut
                if ($text !~ /["']\s*if this isn/) {
                    # If we got this far, someone was happy. Let's retweet.
                    $twitter->retweet({
                        'id' => $_->{id},
                    });
                }
            }
        }
    }
    $opts{page}++;
    if (!exists $opts{since_id}) {
        last;
    }
}

