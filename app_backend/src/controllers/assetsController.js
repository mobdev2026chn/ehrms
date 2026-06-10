const Asset = require('../models/Asset');
const Staff = require('../models/Staff');
const AssetType = require('../models/AssetType'); // Required for populate
const Branch = require('../models/Branch'); // Required for populate

// @desc    Get all assets assigned to the current user
// @route   GET /api/assets
// @access  Private
const getAssets = async (req, res) => {
    try {
        const currentUser = req.user;
        const staff = req.staff;

        if (!currentUser && !staff) {
            return res.status(401).json({
                success: false,
                error: { message: 'Not authenticated' }
            });
        }

        // Get company/business ID
        let businessId;
        if (staff && staff.businessId) {
            businessId = staff.businessId;
        } else if (currentUser && currentUser.companyId) {
            businessId = currentUser.companyId;
        } else {
            return res.status(400).json({
                success: false,
                error: { message: 'Company ID is required' }
            });
        }

        const { status, type, search, branchId, page = 1, limit = 10 } = req.query;

        // Build base query
        const baseQuery = {
            businessId: businessId
        };

        // If user is an Employee, automatically filter by their assigned assets
        if ((currentUser && currentUser.role === 'Employee') || (staff && !staff.isAdmin)) {
            // Find the staff record for this user
            let staffRecord = staff;
            if (!staffRecord && currentUser) {
                staffRecord = await Staff.findOne({ userId: currentUser._id });
            }
            
            if (staffRecord) {
                baseQuery.assignedTo = staffRecord._id;
            } else {
                // If no staff record found, return empty results
                return res.json({
                    success: true,
                    data: {
                        assets: [],
                        pagination: {
                            page: Number(page),
                            limit: Number(limit),
                            total: 0,
                            pages: 0
                        }
                    }
                });
            }
        }

        if (status && status !== 'All Assets') {
            baseQuery.status = status;
        }
        if (type) {
            // `type` is an AssetType *name* coming from the filter dropdown.
            // It can be stored on the asset in any of three places: the linked
            // AssetType (assetTypeId), the denormalized `type` string, or the
            // `assetCategory` string. Match against all of them so the filter
            // works regardless of how the asset was created.
            const matchingTypes = await AssetType.find({
                businessId: businessId,
                name: type
            }).select('_id');
            const typeIds = matchingTypes.map((t) => t._id);

            baseQuery.$or = [
                { type: type },
                { assetCategory: type },
                ...(typeIds.length ? [{ assetTypeId: { $in: typeIds } }] : [])
            ];
        }
        if (branchId) {
            baseQuery.branchId = branchId;
        }

        // Build search query
        let query = baseQuery;
        if (search) {
            const searchConditions = [
                { name: { $regex: search, $options: 'i' } },
                { serialNumber: { $regex: search, $options: 'i' } },
                { type: { $regex: search, $options: 'i' } },
                { assetCategory: { $regex: search, $options: 'i' } },
                { location: { $regex: search, $options: 'i' } }
            ];
            query = {
                $and: [
                    baseQuery,
                    { $or: searchConditions }
                ]
            };
        }

        const skip = (Number(page) - 1) * Number(limit);

        const assets = await Asset.find(query)
            .populate('assignedTo', 'name employeeId')
            .populate('assetTypeId', 'name')
            .populate('branchId', 'branchName branchCode')
            .skip(skip)
            .limit(Number(limit))
            .sort({ createdAt: -1 });

        const total = await Asset.countDocuments(query);

        res.json({
            success: true,
            data: {
                assets,
                pagination: {
                    page: Number(page),
                    limit: Number(limit),
                    total,
                    pages: Math.ceil(total / Number(limit))
                }
            }
        });
    } catch (error) {
        console.error('Error fetching assets:', error);
        res.status(500).json({
            success: false,
            error: { message: error.message || 'Failed to fetch assets' }
        });
    }
};

// @desc    Get asset by ID
// @route   GET /api/assets/:id
// @access  Private
const getAssetById = async (req, res) => {
    try {
        const currentUser = req.user;
        const staff = req.staff;

        if (!currentUser && !staff) {
            return res.status(401).json({
                success: false,
                error: { message: 'Not authenticated' }
            });
        }

        // Get company/business ID
        let businessId;
        if (staff && staff.businessId) {
            businessId = staff.businessId;
        } else if (currentUser && currentUser.companyId) {
            businessId = currentUser.companyId;
        } else {
            return res.status(400).json({
                success: false,
                error: { message: 'Company ID is required' }
            });
        }

        const asset = await Asset.findById(req.params.id)
            .populate('assignedTo', 'name employeeId')
            .populate('assetTypeId', 'name')
            .populate('branchId', 'branchName branchCode');

        if (!asset) {
            return res.status(404).json({
                success: false,
                error: { message: 'Asset not found' }
            });
        }

        // Check access - asset must belong to the same business
        if (asset.businessId.toString() !== businessId.toString()) {
            return res.status(403).json({
                success: false,
                error: { message: 'Access denied' }
            });
        }

        res.json({
            success: true,
            data: { asset }
        });
    } catch (error) {
        console.error('Error fetching asset:', error);
        res.status(500).json({
            success: false,
            error: { message: error.message || 'Failed to fetch asset' }
        });
    }
};

// @desc    Get all asset types
// @route   GET /api/assets/types
// @access  Private
const getAssetTypes = async (req, res) => {
    try {
        const currentUser = req.user;
        const staff = req.staff;

        if (!currentUser && !staff) {
            return res.status(401).json({
                success: false,
                error: { message: 'Not authenticated' }
            });
        }

        let businessId;
        if (staff && staff.businessId) {
            businessId = staff.businessId;
        } else if (currentUser && currentUser.companyId) {
            businessId = currentUser.companyId;
        } else {
            return res.status(400).json({
                success: false,
                error: { message: 'Company ID is required' }
            });
        }

        const assetTypes = await AssetType.find({ businessId: businessId })
            .sort({ name: 1 });

        res.json({
            success: true,
            data: { assetTypes }
        });
    } catch (error) {
        console.error('Error fetching asset types:', error);
        res.status(500).json({
            success: false,
            error: { message: error.message || 'Failed to fetch asset types' }
        });
    }
};

// @desc    Get all branches
// @route   GET /api/branches
// @access  Private
const getBranches = async (req, res) => {
    try {
        const currentUser = req.user;
        const staff = req.staff;

        if (!currentUser && !staff) {
            return res.status(401).json({
                success: false,
                error: { message: 'Not authenticated' }
            });
        }

        let businessId;
        if (staff && staff.businessId) {
            businessId = staff.businessId;
        } else if (currentUser && currentUser.companyId) {
            businessId = currentUser.companyId;
        } else {
            return res.status(400).json({
                success: false,
                error: { message: 'Company ID is required' }
            });
        }

        const branches = await Branch.find({ 
            businessId: businessId,
            status: 'ACTIVE'
        })
            .select('_id branchName branchCode')
            .sort({ isHeadOffice: -1, branchName: 1 });

        res.json({
            success: true,
            data: { branches }
        });
    } catch (error) {
        console.error('Error fetching branches:', error);
        res.status(500).json({
            success: false,
            error: { message: error.message || 'Failed to fetch branches' }
        });
    }
};

module.exports = {
    getAssets,
    getAssetById,
    getAssetTypes,
    getBranches
};
