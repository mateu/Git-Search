use strict;
use warnings FATAL => 'all';
use 5.008001;
use ExtUtils::MakeMaker;
(do 'maint/Makefile.PL.include' or die $@) unless -f 'META.yml';

my %RUN_DEPS = (
  'Moo' => 1.002000,
  'JSON' => 2.57,
  'Web::Simple' => 0.020,
  'Furl' => 2.16,
);
my %BUILD_DEPS = (
  'Test::More'  =>  0.96,
);

WriteMakefile(
  NAME => 'Git::Search',
  VERSION_FROM => 'lib/Git/Search.pm',
  PREREQ_PM => {
    %RUN_DEPS,
  },
  BUILD_REQUIRES => {
    %BUILD_DEPS,
  },
  META_ADD => {
    resources => {
      repository  => 'git://github.com/mateu/Git-Search.git',
      bugtracker  => 'http://rt.cpan.org/NoAuth/Bugs.html?Dist=Git-Search',
    },
  },
  LICENSE => 'perl',
);
