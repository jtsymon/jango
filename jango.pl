#!/usr/bin/env perl 

use strict;
use warnings;
use utf8;
use LWP::UserAgent;
use HTTP::Request::Common;
use JSON;
use POSIX 'strftime';
use Term::ReadKey;
use File::Basename;

my $HELP = basename($0) . "
Commands:
    -h | --help     Displays this help message
    <station id>    Plays the given station
    <artist name>   Finds a station for the artist, and plays it
Input:
    p               Toggles pause on the current song
    n               Starts playing the next song
    q               Quits the player
";
my $station;

# Commandline argument parsing
# Checks for a station id. Artist searching is handled later.
if ($#ARGV == -1) {
    print $HELP;
    exit 1;
} elsif ($#ARGV == 0) {
    for ($ARGV[0]) {
        /^[\d]+$/ and do {
            $station = $_;
            last;
        };
        /^-h$/ or /^--help$/ and do {
            print $HELP;
            exit 0;
        };
    }
}

my $UA = LWP::UserAgent->new;
$UA->cookie_jar({});
my $playing = 1;
my ($player, $pid);
my ($url, $tags);

# Downloads a webpage via HTTP get, and die if the request fails
# (used to avoid duplicating error checking code)
# returns the webserver's result if successful
sub get {
    my $response = $UA->request(GET shift);
    $response->is_success or do {
        my $message = shift;
        if (defined $message) {
            die $message . ': ' . $response->status_line . '\n';
        } else {
            die $response->status_line . '\n';
        }
    };
    return $response->decoded_content;
}

# Preloads the next song's details to minimise load times
sub prepare_song {
    # get next song
    $url = decode_json(get 'http://www.jango.com/streams/' . $station, 'Failed to retrieve stream')->{'url'};
    # get song details
    ($tags) = ((get 'http://www.jango.com/players/usd?ver=7', 'Failed to retrieve song details') =~ /_jm\.song_info[\s]*=(.*);/i);
    $tags = decode_json $tags;
}

# Plays a song, and preloads the next song
# IMPORTANT: Must only be called after the previous player has died
# (or bad things will happen)
sub play_song {
    print((strftime '%Y-%m-%d %H:%M', localtime), ' | ', $tags->{'artist'}, ' - ', $tags->{'song'}, "\n");
    $pid = open $player, '| mplayer -really-quiet ' . $url . ' 2>/dev/null';
    # Enable unbuffered output to the player so we can control it
    my $previous_fh = select($player);
    $| = 1;
    select($previous_fh);
    prepare_song;
}

# When the song ends (or is skipped), start the next song
$SIG{CHLD} = sub {
    close $player;
    $playing and play_song;
};

# If we don't have a station to play, we must have been given an artist name to search
unless (defined $station) {
    my $artist = join '+', @ARGV;
    $artist =~ s/[\s]+/+/g;
    my $html = get 'http://www.jango.com/music/' . $artist, 'Failed to retrieve station list';
    $html =~ s/\n//g;
    ($station, my $title) = ($html =~ /<a href="\/stations\/([\d]+)\/play".*?>([^<]*Radio).*?<\/a>/mi) or die 'No results found for ' . $artist . "\n";
    print "Found station ", $station, " - ", $title, "\n";
};

# Connect to jango in order to get cookies
get 'http://www.jango.com/stations/' . $station . '/tunein', 'Failed to connect to jango';
prepare_song;
play_song;
# Enable unbuffered user input
ReadMode 3;
# Handle user input
while ($playing) {
    my $key = ReadKey 0;
    for ($key) {
        /^q$/ and do {
            $playing = 0;
            print $player 'q';
            waitpid $pid, 0;
            last;
        };
        /^p$/ and do {
            print $player 'p';
            last;
        };
        /^n$/ and do {
            print $player 'q';
            last;
        };
    }
}
