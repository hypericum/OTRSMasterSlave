# --
# Copyright (C) 2001-2016 OTRS AG, http://otrs.com/
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (AGPL). If you
# did not receive this file, see http://www.gnu.org/licenses/agpl.txt.
# --

package Kernel::Output::HTML::TicketBulk::MasterSlave;

use strict;
use warnings;

our @ObjectDependencies = (
    'Kernel::Config',
    'Kernel::Output::HTML::Layout',
    'Kernel::System::DynamicField',
    'Kernel::System::DynamicField::Backend',
    'Kernel::System::Ticket',
    'Kernel::System::Web::Request',
);

sub new {
    my ( $Type, %Param ) = @_;

    # allocate new hash for object
    my $Self = {%Param};
    bless( $Self, $Type );

    my $ConfigObject = $Kernel::OM->Get('Kernel::Config');

    # get master/slave dynamic field
    $Self->{MasterSlaveDynamicField}    = $ConfigObject->Get('MasterSlave::DynamicField')    || '';
    $Self->{MasterSlaveAdvancedEnabled} = $ConfigObject->Get('MasterSlave::AdvancedEnabled') || 0;

    if ( $Self->{MasterSlaveDynamicField} ) {
        $Self->{DynamicFieldConfig} = $Kernel::OM->Get('Kernel::System::DynamicField')->DynamicFieldGet(
            Name => $Self->{MasterSlaveDynamicField},
        );
    }

    return $Self;
}

sub Display {
    my ( $Self, %Param ) = @_;

    # if there is no configured dynamic field or if advanced mode is not enable, there is nothing to do
    return if !$Self->{MasterSlaveDynamicField};
    return if !$Self->{MasterSlaveAdvancedEnabled};

    my $ServerError;
    my $ErrorMessage;
    if ( exists $Param{Errors}->{ $Self->{DynamicFieldConfig}->{Name} } ) {
        $ServerError  = 1;
        $ErrorMessage = $Param{Errors}->{ $Self->{DynamicFieldConfig}->{Name} };
    }

    my $PossibleValuesFilter = $Self->_GetMasterSlaveData(
        %Param,
        MasterSlaveDynamicField => $Self->{MasterSlaveDynamicField},
    );

    # get field HTML
    my $DynamicFieldHTML = $Kernel::OM->Get('Kernel::System::DynamicField::Backend')->EditFieldRender(
        DynamicFieldConfig   => $Self->{DynamicFieldConfig},
        PossibleValuesFilter => $PossibleValuesFilter,
        ServerError          => $ServerError || '',
        ErrorMessage         => $ErrorMessage || '',
        LayoutObject         => $Kernel::OM->Get('Kernel::Output::HTML::Layout'),
        ParamObject          => $Kernel::OM->Get('Kernel::System::Web::Request'),
        Mandatory            => 0,
    );

    # indentation here is on purpose so the HTML will look according to the framework
    my $HTMLString = <<"EOF";
                    $DynamicFieldHTML->{Label}
                    <div class="Field">
                        $DynamicFieldHTML->{Field}
                    </div>
                    <div class="Clear"></div>
EOF

    return $HTMLString;
}

sub Validate {
    my ( $Self, %Param ) = @_;

    # if there is no configured dynamic field or if advanced mode is not enable, there is nothing to do
    return if !$Self->{MasterSlaveDynamicField};
    return if !$Self->{MasterSlaveAdvancedEnabled};

    my $PossibleValuesFilter = $Self->_GetMasterSlaveData(
        %Param,
        MasterSlaveDynamicField => $Self->{MasterSlaveDynamicField},
    );

    my $ValidationResult = $Kernel::OM->Get('Kernel::System::DynamicField::Backend')->EditFieldValueValidate(
        DynamicFieldConfig   => $Self->{DynamicFieldConfig},
        PossibleValuesFilter => $PossibleValuesFilter,
        ParamObject          => $Kernel::OM->Get('Kernel::System::Web::Request'),
        Mandatory            => 1,
    );

    if ( $ValidationResult->{ServerError} ) {
        return (
            {
                ErrorKey   => $Self->{DynamicFieldConfig}->{Name},
                ErrorValue => $ValidationResult->{ErrorMessage},
            }
        );
    }

    return;
}

sub Store {
    my ( $Self, %Param ) = @_;

    # if there is no configured dynamic field or if advanced mode is not enable, there is nothing to do
    return 1 if !$Self->{MasterSlaveDynamicField};
    return 1 if !$Self->{MasterSlaveAdvancedEnabled};

    # get needed objects
    my $DynamicFieldBackendObject = $Kernel::OM->Get('Kernel::System::DynamicField::Backend');

    # extract the dynamic field value form the web request
    my $DynamicFieldValue = $DynamicFieldBackendObject->EditFieldValueGet(
        DynamicFieldConfig => $Self->{DynamicFieldConfig},
        ParamObject        => $Kernel::OM->Get('Kernel::System::Web::Request'),
        LayoutObject       => $Kernel::OM->Get('Kernel::Output::HTML::Layout'),
    );

    # set the value
    my $Success = $DynamicFieldBackendObject->ValueSet(
        DynamicFieldConfig => $Self->{DynamicFieldConfig},
        ObjectID           => $Param{TicketID},
        Value              => $DynamicFieldValue,
        UserID             => $Param{UserID},
    );

    return 1;
}

sub _GetMasterSlaveData {
    my ( $Self, %Param ) = @_;

    # get config object
    my $ConfigObject = $Kernel::OM->Get('Kernel::Config');

    # get master slave config
    my $UnsetMasterSlave  = $ConfigObject->Get('MasterSlave::UnsetMasterSlave')  || 0;
    my $UpdateMasterSlave = $ConfigObject->Get('MasterSlave::UpdateMasterSlave') || 0;

    my %Data = (
        ''     => '-',
        Master => 'New Master Ticket',
    );

    if ($UnsetMasterSlave) {
        $Data{UnsetMaster} = 'Unset Master Tickets';
        $Data{UnsetSlave}  = 'Unset Slave Tickets';
    }

    # get needed objects
    my $TicketObject = $Kernel::OM->Get('Kernel::System::Ticket');
    my $LayoutObject = $Kernel::OM->Get('Kernel::Output::HTML::Layout');

    if ($UpdateMasterSlave) {

        my @TicketIDs = $TicketObject->TicketSearch(
            Result => 'ARRAY',

            # master slave dynamic field
            'DynamicField_' . $Param{MasterSlaveDynamicField} => {
                Equals => 'Master',
            },

            StateType  => 'Open',
            Limit      => 60,
            UserID     => $Param{UserID},
            Permission => 'ro',
        );

        TICKETID:
        for my $TicketID (@TicketIDs) {

            # get each ticket from the search results
            my %CurrentTicket = $TicketObject->TicketGet(
                TicketID => $TicketID
            );
            next TICKETID if !%CurrentTicket;

            $Data{"SlaveOf:$CurrentTicket{TicketNumber}"}
                = $LayoutObject->{LanguageObject}->Translate('Slave of Ticket#')
                . "$CurrentTicket{TicketNumber}: $CurrentTicket{Title}";
        }
    }
    return \%Data;

}
1;
