sub mk { my $n = shift; return { inc => sub { $n++ }, get => sub { $n } } } my $c = mk(5); $c->{inc}->() for 1..3; print $c->{get}->(), "\n";
