sub mk { my $c=shift; return { inc=>sub { ++$c }, get=>sub { $c } } } my $o=mk(5); my $p=mk(1); $o->{inc}->() for 1..2; $p->{inc}->(); print $o->{get}->(), $p->{get}->(), "\n";
