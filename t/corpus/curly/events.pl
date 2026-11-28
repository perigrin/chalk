# An event bus: handlers registered by name with priorities, run in
# order, able to stop the event or to fail without stopping the others;
# handlers that remove themselves; and a log of everything that ran.
use v5.42;

my %handlers;
my @log;
my $next_id = 1;

sub on ($event, $handler, $priority = 0) {
    my $id = $next_id++;
    push @{ $handlers{$event} }, { id => $id, run => $handler, priority => $priority };
    return $id;
}

sub off ($event, $id) {
    my $before = @{ $handlers{$event} // [] };
    $handlers{$event} = [ grep { $_->{id} != $id } @{ $handlers{$event} // [] } ];
    return $before - @{ $handlers{$event} };
}

sub emit ($event, %data) {
    my @list = sort { $b->{priority} <=> $a->{priority} || $a->{id} <=> $b->{id} } @{ $handlers{$event} // [] };
    my $ran = 0;
    for my $h (@list) {
        $ran++;
        my $result;
        try {
            $result = $h->{run}->(\%data);
        } catch ($e) {
            chomp $e;
            push @log, "$event: handler $h->{id} failed: $e";
            next;
        }
        if (($result // '') eq 'stop') {
            push @log, "$event: stopped by handler $h->{id}";
            last;
        }
    }
    return $ran;
}

on(greet => sub ($d) { push @log, "hello, $d->{name}"; return });
on(greet => sub ($d) { push @log, "(priority) checking $d->{name}"; return }, 10);
on(greet => sub ($d) { die "no shouting\n" if $d->{name} eq uc $d->{name}; push @log, "nice name"; return });
my $once;
$once = on(greet => sub ($d) { push @log, "first greeting!"; off("greet", $once); return }, 5);

on(save => sub ($d) { return 'stop' if $d->{readonly}; push @log, "validated"; return }, 1);
on(save => sub ($d) { push @log, "saved $d->{file}"; return });

say "greet ran ", emit(greet => (name => "Ann")), " handlers";
say "greet ran ", emit(greet => (name => "BOB")), " handlers";
say "save ran ", emit(save => (file => "a.txt")), " handlers";
say "save ran ", emit(save => (file => "b.txt", readonly => 1)), " handlers";
say "nobody listens: ", emit("quit");

my $counter = 0;
my $tick = on(tick => sub ($d) { $counter += $d->{by}; return });
emit(tick => (by => $_)) for 1 .. 4;
say "removed ", off("tick", $tick), " tick handler; again ", off("tick", $tick);
emit(tick => (by => 100));
say "counter: $counter";
say $_ for @log;
