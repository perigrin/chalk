my $n = 0; my $inc = sub { $n++ }; my $get = sub { $n }; $inc->(); $n += 10; $inc->(); print $get->(), "\n";
