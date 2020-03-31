use Mojo::Base -strict;

BEGIN { $ENV{MOJO_REACTOR} = 'Mojo::Reactor::Poll' }

use Mojolicious::Lite;
use Test::Mojo;
use Test::More;

plan skip_all => 'set TEST_ONLINE to enable this test' unless $ENV{TEST_ONLINE};

# Isolate tests
require Mojo::Pg;
my $pg = Mojo::Pg->new($ENV{TEST_ONLINE});
$pg->db->query('drop schema if exists minion_test_test cascade');
$pg->db->query('create schema minion_test_test');
plugin Minion => {Pg => $pg->search_path(['minion_test_test'])};

app->minion->add_task(
  add => sub {
    my ($job, $x, $y) = @_;
    return $job->finish($x + $y);
  }
);

app->minion->add_task(
  identity => sub {
    my ($job, $x) = @_;
    return $job->finish($x);
  }
);

app->minion->add_task(
  spawn_more => sub {
    my ($job, $x) = @_;
    $job->app->minion->enqueue(
      spawn_more => [rand(0xffffff)],
      {parents => [$job->id]}
    ) unless @{$job->info->{parents}};
    $job->finish($x);
  }
);

app->start;

my $t = Test::Mojo->with_roles('+Minion')->new;

$t->task_exists('add')->enqueue_ok(add => [1, 1] => 2 => 'test add')
  ->enqueue_ok(identity => [[qw(foo bar)]] => [qw(foo bar)] => 'test identity')
  ->perform_jobs_ok();

$t->enqueue_ok(
  add => [100, 9000] => sub {
    my $job = shift;
    is $job->info->{result}, 9100, 'correct';
    is_deeply $job->info->{children}, [], 'no children';
  } => 'slightly bigger numbers'
)->perform_jobs_ok;

my ($parents, $children);
$t->enqueue_ok(spawn_more => [9] => sub {
  my $job = shift;
  my $info  = $job->info;
  $children = $info->{children};
  $parents  = [$job->id];
  is $info->{result}, 9, 'correct';
}, 'ok')->perform_jobs_ok;

$t->job_is(@$children, sub {
  my $job = shift;
  is_deeply $job->info->{parents}, $parents, 'linkage correct';
  ok $job->info->{result}, 'has result';
}, 'fails')->perform_jobs_ok;

subtest "tests fail correctly" => sub {
  {
    local $TODO = "overloaded to check task_exists";
    $t->task_exists('delete_databases');
  }
  is $t->success, '', 'correct';
};

$t->perform_jobs_ok({});

# Clean up once we are done
$pg->db->query('drop schema minion_test_test cascade');

done_testing;
