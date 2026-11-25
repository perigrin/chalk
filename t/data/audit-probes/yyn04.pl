eval { eval { die "in\n" }; die "re:$@" if $@; }; print $@;
