import AppBar from '@material-ui/core/AppBar';
import Button from '@material-ui/core/Button';
import { withStyles } from '@material-ui/core/styles';
import Toolbar from '@material-ui/core/Toolbar';
import Typography from '@material-ui/core/Typography';
import HomeIcon from '@material-ui/icons/Home';
import PropTypes from 'prop-types';
import React from 'react';
import { Link } from "react-router-dom";

const styles = {
  root: {
    flexGrow: 1,
  },
  flex: {
    flex: 1,
  },
  menuButton: {
    marginLeft: -12,
    marginRight: 20,
  },
};

class CustomAppBar extends React.Component {
  render() {
    const { classes } = this.props;
    return (
      <div className={classes.root}>
        <AppBar position="static" color="default">
          <Toolbar>
            <Typography variant="h6" color="inherit" className={classes.flex}>
              Decentralized &amp; Collaborative AI on Blockchain
            </Typography>
            {/* Disable adding new models through the UI for now until we standardize the process.
            <Link to='/new'>
              <Button className={classes.button}>
                  <AddIcon />
                  Create New Model
              </Button>
            </Link>
            */}
            <Link to="/">
              <Button>
                <HomeIcon />
              </Button>
            </Link>
          </Toolbar>
        </AppBar>
      </div>
    );
  }
}

CustomAppBar.propTypes = {
  classes: PropTypes.object.isRequired,
};

export default withStyles(styles)(CustomAppBar);