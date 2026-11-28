our %h = (a=>1); eval { local $h{a} = 2; die "z\n" }; print "$h{a}$@";
