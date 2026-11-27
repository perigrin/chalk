sub one { 1 } my $v = one(); { no warnings; *one = sub { 3 }; } print $v, one(), "\n";
