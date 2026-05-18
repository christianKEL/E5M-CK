# ─── Personnaliser le logo de boot (2e écran uniquement) ───

# 1. Préparer l'image perso (480×272 JPG) dans /usr/data/
wget -O /usr/data/my_logo.jpg <URL_DE_TON_IMAGE>

# 2. Sauvegarder les originaux depuis /rom/ (ROM de référence, intouchable)
mkdir -p /usr/data/logo_originals
cp /rom/etc/logo/*.jpg  /usr/data/logo_originals/
cp /rom/etc/logo/*.jpeg /usr/data/logo_originals/

# 3. Remplacer tous les variants de logo
for f in /etc/logo/*.jpg /etc/logo/*.jpeg; do
  cp /usr/data/my_logo.jpg "$f"
done

# 4. Reboot
sync
reboot

# ─── Restauration en cas de besoin ───
cp /rom/etc/logo/*.jpg  /etc/logo/
cp /rom/etc/logo/*.jpeg /etc/logo/
sync
reboot
