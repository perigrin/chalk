sub mk { my $n = shift; { inc => sub { $n++ }, get => sub { $n } } } my $o = mk(5); my $p = mk(1); $o->{inc}->(); print $o->{get}->(), $p->{get}->(), "\n";
