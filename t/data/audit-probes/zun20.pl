eval { die { code=>5 } }; print $@->{code}, "\n";
