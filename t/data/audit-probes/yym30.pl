{ no warnings; print join(",", undef..2), "|", join(",", ""..""), "|", join(",", "a".."a"), "|", join(",", "09".."08"), "|", join(",", "zy".."b"), "|", scalar(my @x = ("b".."a")), "\n"; }
