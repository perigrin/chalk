sub one { 1 } sub two { 2 } sub chg { no warnings; *one = \&two } my $v = one(); chg(); print $v, one(), "\n";
