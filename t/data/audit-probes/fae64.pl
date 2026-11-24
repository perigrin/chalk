my $x = eval { my @a=(1,2,3); $a[5] // die "undef\n" }; print $@;
