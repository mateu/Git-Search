#use strictures 1;
use IO::All;
use JSON;
use HTTP::Request;
use LWP::UserAgent;
use IPC::System::Simple qw/ capture /;
use Git::Search::Config;

use DDP;

my $config = Git::Search::Config->new->config;
my $work_tree = $config->{work_tree};
my $git_dir = $work_tree . '.git';
my @files = capture('git', "--git-dir=${git_dir}", "--work-tree=${work_tree}", 
  'ls-tree', '--full-tree', '-r', 'HEAD');
@files = map { [split /\s+/, $_] } @files;
my $mode = 0;
my $type = 1;
my $id   = 2;
my $name = 3;
# Restrict to just lib subdirectory for now and .pm files
my @sub_dirs = @{$config->{sub_dirs}};
@sub_dirs = map { '^' . $_ } @sub_dirs;
my $sub_dirs = join '|', @sub_dirs;
@files = grep { $_->[$name] =~ m!($sub_dirs)! } @files;
#@files = grep { $_->[$name] =~ m|\.pm$| } @files;

#p(@files);
my @structs;
foreach my $file (@files) {
    my $filename = $work_tree . $file->[$name];
    my $content < io $filename;
#p($content);
    push @structs , {
        content => $content,
        name => $file->[$name],
        commit_id => $file->[$id],
        type => $file->[$type],
        mode => $file->[$mode],
    }
}
# Index the docs
foreach my $doc (@structs) {
    warn "creating ", $doc->{name};
    warn "content ", $doc->{content};
    create_doc($doc);
}

sub base_url { return $config->{base_url} }

sub create_doc {
    my ($doc) = @_;
    my $req = HTTP::Request->new(POST => base_url());
    $req->content_type('application/json');
    my $json_doc = encode_json($doc);
#p($json_doc);
    $req->content($json_doc);
    my $ua = LWP::UserAgent->new;
    my $res = $ua->request($req);
#    p($res);
}

my $search = {
    query => { match => {content => 'MooseX'}},
};
my $search_json = encode_json($search);
my $base_url = base_url();
my $url = $base_url . '_search';
my $req = HTTP::Request->new(POST => $url);
$req->content_type('application/json');
$req->content($search_json);
my $ua = LWP::UserAgent->new;
my $res = $ua->request($req);
warn "RESPONSE: ";
my $output = decode_json($res->content);
p($output->{hits}->{hits}->[0]);
