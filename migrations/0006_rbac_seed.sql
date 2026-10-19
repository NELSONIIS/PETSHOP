-- Reference data that the application cannot run without: roles and permissions.
INSERT INTO roles (code, name, is_staff, description) VALUES
 ('buyer','Buyer',false,'Browses pets and may hold a buyer membership'),
 ('seller','Seller',false,'Lists pets under a seller subscription'),
 ('moderator','Moderator',true,'Verifies sellers and moderates listings'),
 ('finance','Finance',true,'Views payments and issues refunds'),
 ('support','Support agent',true,'Handles reports, disputes and user support'),
 ('super_admin','Super administrator',true,'Full platform access');

INSERT INTO permissions (code, description) VALUES
 ('dashboard.view','View admin overview'),
 ('users.view','View users'),
 ('users.manage','Suspend / reinstate users'),
 ('roles.manage','Grant or revoke staff roles'),
 ('sellers.verify','Review seller verification and documents'),
 ('listings.moderate','Approve, reject and suspend listings'),
 ('catalog.manage','Manage categories and breeds'),
 ('plans.manage','Manage subscription plans'),
 ('subscriptions.view','View subscription records'),
 ('payments.view','View payments and invoices'),
 ('refunds.create','Issue refunds'),
 ('reports.manage','Handle reports, enquiries abuse and disputes'),
 ('content.manage','Manage homepage content, legal pages and templates'),
 ('settings.manage','Change platform settings'),
 ('audit.view','View audit logs');

INSERT INTO role_permissions (role_code, permission_code)
SELECT 'super_admin', code FROM permissions;
INSERT INTO role_permissions (role_code, permission_code) VALUES
 ('moderator','dashboard.view'),('moderator','users.view'),('moderator','sellers.verify'),('moderator','listings.moderate'),('moderator','reports.manage'),
 ('finance','dashboard.view'),('finance','users.view'),('finance','subscriptions.view'),('finance','payments.view'),('finance','refunds.create'),
 ('support','dashboard.view'),('support','users.view'),('support','reports.manage'),('support','subscriptions.view'),('support','payments.view');
