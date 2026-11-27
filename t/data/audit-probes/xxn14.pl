sub one { 1 } sub chg { no warnings; *one = sub { 3 } } chg(); print one(), "\n";
