use strict;
use warnings;
use Git::Search;
use 5.010;

my $gs = Git::Search->new;
my $hits = $gs->hits;
say "\nFound ", $gs->search_phrase, " in files: \n";
foreach my $hit (@{$gs->hits}) {
    say "  ", $hit->{_source}->{name};
    my $highlights = $hit->{highlight};
    my @content = @{$highlights->{content}};
}
print "\n";
