require_relative 'preview_data'

# Preview PallasTrade invitation emails at /rails/mailers/pallastrade/invitation
class PallasTrade::InvitationPreview < ActionMailer::Preview
  include PallasTrade::PreviewData::LocaleParam

  def invitation_email
    PallasTrade::InvitationMailer.invitation_email(pending_invitation)
  end

  def invitation_accepted
    PallasTrade::InvitationMailer.invitation_accepted(accepted_invitation)
  end

  private

  def pending_invitation
    return example_invitation if locale.present?

    PallasTrade::Invitation.pending.last || example_invitation
  end

  def accepted_invitation
    return example_invitation(accepted: true) if locale.present?

    PallasTrade::Invitation.accepted.last || example_invitation(accepted: true)
  end

  # Build an in-memory invitation so the preview works on a database with no
  # invitations. When the preview toolbar requests a locale, its store carries
  # that locale. Never saved, so no records are created.
  def example_invitation(accepted: false)
    store = PallasTrade::PreviewData.store(locale)
    admin = PallasTrade::PreviewData.admin_user
    PallasTrade::Invitation.new(
      id: 0,
      email: 'invitee@example.com',
      resource: store,
      inviter: admin,
      invitee: accepted ? admin : nil,
      role: PallasTrade::Role.first || PallasTrade::Role.new(name: 'admin'),
      token: 'preview-token',
      status: accepted ? 'accepted' : 'pending',
      expires_at: 7.days.from_now
    )
  end
end
