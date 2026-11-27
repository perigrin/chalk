sub one { 1 } sub ap { no warnings; *one = $_[0] } ap(sub { 4 }); print one(), "\n";
