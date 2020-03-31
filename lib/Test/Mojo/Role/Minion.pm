package Test::Mojo::Role::Minion;

use Mojo::Base -role;
use Mojo::IOLoop;
use Mojo::Util qw(encode);

requires qw(app test);

sub enqueue_ok {
  my ($self, $task, $args, $result, $desc) = @_;
  my $id = $self->app->minion->enqueue($task => $args);
  $self->{job_expectations}{$id}
    = [$result, ref($result) || '', _desc($desc || "$task ok")];
  $self->test(ok => $id => "enqueue '$task' ok");
  return $self;
}

sub job_is {
  my ($self, $id, $exp, $desc) = @_;
  $self->_job_ok($self->app->minion->job($id), $exp, ref($exp) || '', $desc);
}

sub perform_jobs_ok {
  my ($self, $opts) = (shift, shift || {});
  my $minion = $self->app->minion;
  my $jobs   = $self->{job_expectations} || {};
  return unless my @ids = keys %$jobs;
  Mojo::IOLoop->delay(sub { $minion->perform_jobs($opts) })
    ->catch(sub { $self->test(fail => shift) })->wait;
  for my $id (sort { $a <=> $b } @ids) {
    my ($exp, $type, $desc) = @{delete $jobs->{$id}};
    $self->_job_ok($minion->job($id), $exp, $type, $desc);
  }
  return $self;
}

sub task_exists {
  my ($self, $task, $desc) = @_;
  $desc = _desc($desc || "Task '$task' exists");
  $self->test(ok => exists($self->app->minion->tasks->{$task}) => $desc);
}


sub _desc { encode 'UTF-8', shift || shift }

sub _job_ok {
  my ($self, $job, $exp, $exp_type, $desc) = @_;
  $self->test(ok => $job, "job exists - $desc");
  local $Test::Builder::Level = $Test::Builder::Level + 1;
  return $self->test(subtest => $desc => $exp => $job)
    if $exp_type eq 'CODE';
  return $self->test(is_deeply => $job->info->{result}, $exp, $desc)
    if $exp_type =~ m{(ARRAY|HASH)};
  return $self->test(is => $job->info->{result}, $exp, $desc);
}

1;

=encoding utf8

=head1 NAME

Test::Mojo::Role::Minion - Testing role for Minion with Mojolicious

=head1 SYNOPSIS

  use Test::Mojo;
  $t = Test::Mojo->with_roles('+Minion')->new;
  $t->task_exists('add')
    ->task_exists('convert')
    ->enqueue_ok(add => [1, 1], 2, $desc)
    ->enqueue_ok(convert => ['image.jpg'], 'image.png', $desc)
    ->perform_jobs_ok;

=head1 DESCRIPTION

=head1 METHODS

L<Test::Mojo::Role::Minion> composes the following chainable methods.

=head2 enqueue_ok

  $t->enqueue_ok($task_name, $input_args, $exp_result, $description);

This will L<Minion/"enqueue"> a task with C<$task_name> and C<$input_args>. The
C<$exp_result> will be tested when L</"perform_jobs_ok"> is called. The tests will
be performed in the same manner as detailed in L</"job_is"> depending on the
type passed in C<$exp_result>.

=head2 job_is

  $t->job_is($job_id, $exp_result, $description);

Test the job matches the C<$exp_result>. C<$exp_result> may be a plain scalar or
an array or hash reference in which cases the job's result will be tested with
either L<Test::More/"is"> or L<Test::More/"is_deeply">. In addition,
C<$exp_result> may be a code rederence in which case a L<Test::More/"subtest">
will be performed passing the code reference the performed L<Minion::Job> to
facilitate testing more than just the result of a job.

=head2 perform_jobs_ok

  $t->perform_jobs_ok($options);

A shortcut to L<Minion/"perform_jobs"> that will test the result for each of the
jobs enqueued using L</"enqueue_ok">.

=head2 task_exists

  $t->task_exists($task_name, $description);

A simple check that the C<$task_name> has been added to the application with
L<Minion/"add_task">.

=cut
