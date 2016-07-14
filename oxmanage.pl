#!/usr/bin/env perl

use strict;
use warnings;

use feature 'say';

use UI::Dialog;
use Switch;
use Text::CSV;
use Data::Dumper;
use Config::Simple;

#########################################
#
# settings
#
#########################################

my @config_files = (
		     "/usr/local/etc/oxtools/config",
		     "/etc/oxtools/config",
                     "./config"
                   );

my $config_file;

for my $cf (@config_files) {
    $config_file = $cf if -r $cf;
}

die "no config file found found" unless $config_file;

my $cfg = new Config::Simple($config_file) or die $!;

our $oxadmin_user = $cfg->param("oxadmin_user")       or die "Missing config oxadmin_user"; 
our $oxadmin_pw   = $cfg->param("oxadmin_password")   or die "Missing config: oxadmin_password"; 
our $context      = $cfg->param("context")            or die "Missing config: context"; 
our $ox_sbin_path = $cfg->param("ox_sbin_path")       or die "Missing config: ox_sbin_path";
our $imapserver   = $cfg->param("imapserver")         or die "imapserver"; 
our $smtpserver   = $cfg->param("smtpserver")         or die "smtpserver"; 

#########################################

our $d = new UI::Dialog(
backtitle  => 'Demo',
title      => 'Default',
height     => 20,
width      => 60,
listheight => 10
);

sub genpw {
    my $pw;
    our @chars = ( 'a' .. 'z', 'A' .. 'Z', '0' .. '9' );
    for (1 .. 10) {
    $pw .= $chars[ rand @chars ];
    }
    return $pw;
}

sub mainmenu {
    return $d->menu(
        text => "What do you want to do?",
        list => [
            'NEWUSER',      'add a new user',
            'NEWGROUP',     'add a new group',
            'USERLIST',     'see current users',
            'GROUPLIST',    'see current groups',
            'CHANGEGROUPS', 'change user\'s groups',
            'DELETEUSER',   'delete a user',
            'DELETEGROUP',  'delete a group',
        ]
    );
}

sub runoxcommand {
    my $command = shift;
    my $params  = shift;
    print raw_runoxcommand($command, $params);
}

sub raw_runoxcommand {
    my $command = shift;
    my $params  = shift;
    print "running: ${command} ${params}\n";

    my $cmd = "${ox_sbin_path}/${command}"
            . " -c 1 -A ${oxadmin_user}"
            . " -P ${oxadmin_pw} ${params}";

    return `$cmd`;

}

sub newuser {
    my $firstname = $d->inputbox( text => "first name" );
    exit unless $firstname;
    my $lastname  = $d->inputbox( text => "last name" );
    exit unless $lastname;
    my $email     = $d->inputbox( text => "email name" );
    exit unless $email;

    my $username  = lcfirst($lastname);
    my $displayname = ucfirst($firstname) . " " . ucfirst($lastname);
    my $password    = genpw();

    my $confirmmsg = "creating user "
                    . "\"$username\" (\"$displayname\", \"$email\"). Continue?";

    exit unless $d->yesno(text => $confirmmsg);

    runoxcommand(
    "createuser",
    "-u \"${username}\" "
        . "-d \"${displayname}\" "
        . "-g \"${firstname}\" "
        . "-s \"${lastname}\" "
        . "-p \"${password}\" "
        . "-e \"${email}\" "
        . "--imaplogin \"${email}\" "
        . "--imapserver \"${imapserver}\" "
        . "--smtpserver \"${smtpserver}\" " );
}

sub newgroup {
    my $groupname = $d->inputbox( text => "group name" );
    exit unless $groupname;

    my $groupdisplayname = $d->inputbox( text => "group display name" );
    exit unless $groupdisplayname;

    my $confirmmsg = "creating group"
                   . " \"$groupname\""
                   . " (\"$groupdisplayname\")."
                   . " Continue?";

    exit unless $d->yesno( text => $confirmmsg );

    runoxcommand("creategroup", "-n $groupname -d \"$groupdisplayname\"");
}

sub userlist {
    runoxcommand("listuser", "");
}

sub parse_csv {
    my $raw_csv       = shift;
    my $id_field_name = shift;
    my $csv           = Text::CSV->new( { binary => 1, auto_diag => 1 } );

    open my $fh, '<', \$raw_csv or die $!;

    # first csv lines contains field names
    # these are used as keys for hashes of rows
    my $row = $csv->getline($fh) or die $!;
    my @keys = @$row;

    my @rows;

    while (my $row = $csv->getline($fh)) {
        push(@rows, $row);
    }

    my %entries;

    # create a hash from each row with keys from first line of csv
    # store them in another hash with the 'id' field als key
    foreach my $r (@rows) {
        my %entry;
        for my $i ( 0 .. $#keys ) {
            $entry{ $keys[$i] } = @$r[$i];
        }
        my $id = $entry{$id_field_name};
        $entries{$id} = \%entry;
    }
    return \%entries;

}

sub deletegroup {
    my $raw_csv = raw_runoxcommand("listgroup", "--csv");
    my $groups = parse_csv($raw_csv, 'id');
    my $menulist = [];

    foreach my $group ( values %$groups ) {
        push(@{$menulist}, $group->{'id'});
        my $item =[ $group->{'name'} . " (" . $group->{displayname} . ")", 0 ];
        push(@{$menulist}, $item);
    }

    my @to_delete_ids = $d->checklist(
        text => "Which Groups do you want to delete?",
        list => $menulist
    );
    exit unless (@to_delete_ids);

    my $delete_group_str;
    foreach my $group_id (@to_delete_ids) {
        $delete_group_str .= $groups->{$group_id}->{'name'} . "\n";
    }

    my $confirmmsg = "deleting the following groups, continue?\n\n";
    $confirmmsg   .= $delete_group_str;
    exit unless $d->yesno( text => $confirmmsg );

    foreach my $group_id (@to_delete_ids) {
        runoxcommand("deletegroup", "-i $group_id");
    }
}

sub deleteuser {
    my $raw_csv = raw_runoxcommand("listuser", "--csv");
    my $users = parse_csv($raw_csv, 'Id');
    my $menulist = [];

    foreach my $user ( values %$users ) {
        push(@{$menulist}, $user->{'Id'});
        my $item = [ $user->{'Name'} . " (" . $user->{Display_name} . ")", 0 ];
        push(@{$menulist}, $item);
    }

    my @to_delete_ids = $d->checklist(
        text => "Which users do you want to delete?",
        list => $menulist
    );
    exit unless (@to_delete_ids);

    my $delete_user_str;
    foreach my $user_id (@to_delete_ids) {
        $delete_user_str .= $users->{$user_id}->{'Name'} . "\n";
    }

    my $confirmmsg = "deleting the following groups, continue?\n\n";
    $confirmmsg   .= $delete_user_str;
    exit unless $d->yesno( text => $confirmmsg );

    foreach my $user_id (@to_delete_ids) {
        runoxcommand("deleteuser", "-i $user_id");
    }
}

sub grouplist {
    runoxcommand("listgroup", "");
}

sub changegroups {
    my $raw_csv = raw_runoxcommand("listuser", "--csv");
    my $users = parse_csv($raw_csv, 'Id');

    $raw_csv = raw_runoxcommand("listgroup", "--csv");
    my $groups = parse_csv($raw_csv, 'id');

    foreach my $key ( keys %{$groups} ) {
        my $group = $groups->{$key};
        my @members = split /,/, $group->{members};
        $group->{members} = \@members;
    }

    my $menulist = [];
    foreach my $user ( values %$users ) {
        push(@{$menulist}, $user->{'Id'});
        my $item = $user->{'Name'} . " (" . $user->{Display_name} . ")";
        push(@{$menulist}, $item);
    }

    my $selected_user = $d->menu(
        text => 'select the user, you want to change',
        list => $menulist
    );
    exit unless ($selected_user);

    $menulist = [];
    my @old_groups;
    foreach my $g ( values %$groups ) {
        my $in_group;
        if ( $selected_user ~~ @{ $g->{members} } ) {
            $in_group = 1;
            push(@old_groups, $g->{id});
        } else {
            $in_group = 0;
        }
            push(@{$menulist}, $g->{id});
            my $item = [ $g->{name} . " (" . $g->{displayname} . ")", $in_group ];
            push(@{$menulist}, $item);
    }

    my @new_groups = $d->checklist(
        text => "Select groups for: " . %{$users->{$selected_user}}->{Display_name},
        list => $menulist
    );

    my @to_remove;
    my @to_add;

    foreach my $gid ( keys %$groups ) {
        my $group   = $groups->{$gid};
        my @members = @{ $group->{members} };
        if ( not( $gid ~~ @new_groups ) and ( $selected_user ~~ @members ) ) {
            push( @to_remove, $gid );
        }
        if ( ( $gid ~~ @new_groups ) and ( not( $selected_user ~~ @members ) ) ) {
            push( @to_add, $gid );
        }
    }

    foreach my $g (@to_remove) {
        runoxcommand( "changegroup", "-i $g -r $selected_user" );
    }

    foreach my $g (@to_add) {
        runoxcommand( "changegroup", "-i $g -a $selected_user" );
    }

}

my $choice = mainmenu;

switch ($choice) {
    case 'NEWUSER'      { newuser() }
    case 'NEWGROUP'     { newgroup() }
    case 'USERLIST'     { userlist() }
    case 'GROUPLIST'    { grouplist() }
    case 'CHANGEGROUPS' { changegroups() }
    case 'DELETEUSER'   { deleteuser() }
    case 'DELETEGROUP'  { deletegroup() }
    else                { exit }
}
