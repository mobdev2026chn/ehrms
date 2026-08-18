const { getDevicesList, storeScreenshot, getDeviceScreenshots } = require('../db/mongo');

async function getAllDevices(req, res) {
  try {
    const businessId = req.user?.businessId || req.query.businessId;
    const devices = await getDevicesList(businessId);
    res.json({ success: true, devices });
  } catch (err) {
    console.error('[Device] Error fetching devices:', err);
    res.status(500).json({ error: 'Failed to fetch devices' });
  }
}

async function postScreenshot(req, res) {
  try {
    const data = req.body || {};
    if (!data.imageBase64 && !data.image) {
      return res.status(400).json({ success: false, error: 'Missing imageBase64 in payload' });
    }
    console.log('[Screenshot] Received upload for device:', data.deviceId || data.hostname, 'Length:', (data.imageBase64 || '').length);
    const saved = storeScreenshot(data);
    res.json({ success: true, screenshot: saved });
  } catch (err) {
    console.error('[Device] Error storing screenshot:', err);
    res.status(500).json({ success: false, error: 'Failed to store screenshot' });
  }
}

async function getScreenshots(req, res) {
  try {
    const deviceId = req.params.deviceId || req.query.deviceId;
    const businessId = req.user?.businessId || req.query.businessId;
    const screenshots = await getDeviceScreenshots(deviceId, businessId);
    res.json({ success: true, screenshots });
  } catch (err) {
    console.error('[Device] Error fetching screenshots:', err);
    res.status(500).json({ success: false, error: 'Failed to fetch screenshots' });
  }
}

module.exports = { getAllDevices, postScreenshot, getScreenshots };
